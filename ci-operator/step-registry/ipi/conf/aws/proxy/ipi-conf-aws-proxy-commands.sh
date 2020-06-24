#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

function generate_proxy_ignition() {
cat > /tmp/proxy.ign << EOF
{
  "ignition": {
    "config": {},
    "security": {
      "tls": {}
    },
    "timeouts": {},
    "version": "2.2.0"
  },
  "passwd": {
    "users": [
      {
        "name": "core",
        "sshAuthorizedKeys": [
          "${ssh_pub_key}"
        ]
      }
    ]
  },
  "storage": {
    "files": [
      {
        "filesystem": "root",
        "path": "/tmp/squid/passwords",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${HTPASSWD_CONTENTS}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/squid.conf",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${SQUID_CONFIG}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid.sh",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${SQUID_SH}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/proxy.sh",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${PROXY_SH}"
        },
        "mode": 420
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "contents": "[Service]\n\nExecStart=bash /tmp/squid.sh\n\n[Install]\nWantedBy=multi-user.target\n",
        "enabled": true,
        "name": "squid.service"
      },
      {
        "dropins": [
          {
            "contents": "[Service]\nExecStart=\nExecStart=/usr/lib/systemd/systemd-journal-gatewayd \\\n  --key=/opt/openshift/tls/journal-gatewayd.key \\\n  --cert=/opt/openshift/tls/journal-gatewayd.crt \\\n  --trust=/opt/openshift/tls/root-ca.crt\n",
            "name": "certs.conf"
          }
        ],
        "name": "systemd-journal-gatewayd.service"
      },
      {
        "enabled": true,
        "name": "systemd-journal-gatewayd.socket"
      }
    ]
  }
}
EOF

aws s3 cp /tmp/proxy.ign ${PROXY_URI}
}

function generate_proxy_template() {
cat > /tmp/04_cluster_proxy.yaml << EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Template for OpenShift Cluster Proxy (EC2 Instance, Security Groups and IAM)

Parameters:
  InfrastructureName:
    AllowedPattern: ^([a-zA-Z][a-zA-Z0-9\-]{0,26})$
    MaxLength: 27
    MinLength: 1
    ConstraintDescription: Infrastructure name must be alphanumeric, start with a letter, and have a maximum of 27 characters.
    Description: A short, unique cluster ID used to tag cloud resources and identify items owned or used by the cluster.
    Type: String
  RhcosAmi:
    Description: Current Red Hat Enterprise Linux CoreOS AMI to use for proxy.
    Type: AWS::EC2::Image::Id
  AllowedProxyCidr:
    AllowedPattern: ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|1[0-9]|2[0-9]|3[0-2]))$
    ConstraintDescription: CIDR block parameter must be in the form x.x.x.x/0-32.
    Default: 0.0.0.0/0
    Description: CIDR block to allow access to the proxy node.
    Type: String
  ClusterName:
    Description: The cluster name used to uniquely identify the proxy load balancer
    Type: String
  PublicSubnet:
    Description: The public subnet to launch the proxy node into.
    Type: AWS::EC2::Subnet::Id
  VpcId:
    Description: The VPC-scoped resources will belong to this VPC.
    Type: AWS::EC2::VPC::Id
  ProxyIgnitionLocation:
    Default: s3://my-s3-bucket/proxy.ign
    Description: Ignition config file location.
    Type: String

Metadata:
  AWS::CloudFormation::Interface:
    ParameterGroups:
    - Label:
        default: "Cluster Information"
      Parameters:
      - InfrastructureName
    - Label:
        default: "Host Information"
      Parameters:
      - RhcosAmi
      - ProxyIgnitionLocation
    - Label:
        default: "Network Configuration"
      Parameters:
      - VpcId
      - AllowedProxyCidr
      - PublicSubnet
      - ClusterName

    ParameterLabels:
      InfrastructureName:
        default: "Infrastructure Name"
      VpcId:
        default: "VPC ID"
      AllowedProxyCidr:
        default: "Allowed ingress Source"
      RhcosAmi:
        default: "Red Hat Enterprise Linux CoreOS AMI ID"
      ProxyIgnitionLocation:
        default: "Bootstrap Ignition Source"
      ClusterName:
        default: "Cluster name"

Resources:
  ProxyIamRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: "Allow"
          Principal:
            Service:
            - "ec2.amazonaws.com"
          Action:
          - "sts:AssumeRole"
      Path: "/"
      Policies:
      - PolicyName: !Join ["-", [!Ref InfrastructureName, "proxy", "policy"]]
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
          - Effect: "Allow"
            Action: "ec2:Describe*"
            Resource: "*"

  ProxyInstanceProfile:
    Type: "AWS::IAM::InstanceProfile"
    Properties:
      Path: "/"
      Roles:
      - Ref: "ProxyIamRole"

  ProxySecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Cluster Proxy Security Group
      SecurityGroupIngress:
      - IpProtocol: tcp
        FromPort: 22
        ToPort: 22
        CidrIp: 0.0.0.0/0
      - IpProtocol: tcp
        ToPort: 3128
        FromPort: 3128
        CidrIp: !Ref AllowedProxyCidr
      - IpProtocol: tcp
        ToPort: 19531
        FromPort: 19531
        CidrIp: !Ref AllowedProxyCidr
      VpcId: !Ref VpcId

  ProxyInstance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: !Ref RhcosAmi
      IamInstanceProfile: !Ref ProxyInstanceProfile
      InstanceType: "i3.large"
      NetworkInterfaces:
      - AssociatePublicIpAddress: "true"
        DeviceIndex: "0"
        GroupSet:
        - !Ref "ProxySecurityGroup"
        SubnetId: !Ref "PublicSubnet"
      UserData:
        Fn::Base64: !Sub
        - '{"ignition":{"config":{"replace":{"source":"\${IgnitionLocation}","verification":{}}},"timeouts":{},"version":"2.1.0"},"networkd":{},"passwd":{},"storage":{},"systemd":{}}'
        - {
          IgnitionLocation: !Ref ProxyIgnitionLocation
        }

Outputs:
  ProxyPublicIp:
    Description: The proxy node public IP address.
    Value: !GetAtt ProxyInstance.PublicIp
EOF
}

# TODO: move to image
curl -L https://github.com/mikefarah/yq/releases/download/3.3.0/yq_linux_amd64 -o /tmp/yq && chmod +x /tmp/yq

EXPIRATION_DATE=$(date -d '4 hours' --iso=minutes --utc)
TAGS="Key=expirationDate,Value=${EXPIRATION_DATE}"

CONFIG="${SHARED_DIR}/install-config.yaml"
aws_subnet="$(/tmp/yq r ${CONFIG} 'platform.aws.subnets[0]')"

region="$(/tmp/yq r ${CONFIG} 'platform.aws.region')"

CLUSTER_NAME=${NAMESPACE}-${JOB_NAME_HASH}
ssh_pub_key=$(<"${CLUSTER_PROFILE_DIR}/ssh-publickey")
# get the VPC ID from the subnet -> subnet.VpcId
# describe the subnet to get vpcID -> https://docs.aws.amazon.com/goto/WebAPI/ec2-2016-11-15/DescribeSubnets
describe="$(aws ec2 describe-subnets --subnet-ids ${aws_subnet})"

vpc_id="$(echo ${describe} | jq -r .[][0].VpcId)"
subnets="$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${vpc_id})"

hosted_zones="$(aws route53 list-hosted-zones-by-vpc --vpc-id ${vpc_id} --vpc-region ${region})"
echo hosted zones: ${hosted_zones}


HTPASSWD_CONTENTS="${CLUSTER_NAME}:"$(openssl passwd -apr1 ${PASSWORD})""
HTPASSWD_CONTENTS="$(echo -e ${HTPASSWD_CONTENTS} | base64 -w0)"

# define squid config
SQUID_CONFIG="$(base64 -w0 << EOF
http_port 3128
cache deny all
access_log stdio:/tmp/squid-access.log all
debug_options ALL,1
shutdown_lifetime 0
auth_param basic program /usr/lib64/squid/basic_ncsa_auth /squid/passwords
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
pid_filename /tmp/proxy-setup
EOF
)"

# define squid.sh
SQUID_SH="$(base64 -w0 << EOF
#!/bin/bash
podman run --entrypoint='["bash", "/squid/proxy.sh"]' --expose=3128 --net host --volume /tmp/squid:/squid:Z ${PROXY_IMAGE}
EOF
)"

# define proxy.sh
PROXY_SH="$(base64 -w0 << EOF
#!/bin/bash
function print_logs() {
    while [[ ! -f /tmp/squid-access.log ]]; do
    sleep 5
    done
    tail -f /tmp/squid-access.log
}
print_logs &
squid -N -f /squid/squid.conf
EOF
)"

cluster_name=${NAMESPACE}-${JOB_NAME_HASH}

CONFIG="${SHARED_DIR}/install-config.yaml"

PASSWORD="$(uuidgen | sha256sum | cut -b -32)"

# create ignition entries for certs and script to start squid and systemd unit entry
# create the proxy stack and then get its IP
PROXY_URI="s3://${CLUSTER_NAME}/proxy.ign"

generate_proxy_ignition
generate_proxy_template

aws cloudformation create-stack \
  --stack-name "${CLUSTER_NAME}-proxy" \
  --template-body "$(cat "/tmp/04_cluster_proxy.yaml")" \
  --tags "${TAGS}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
  ParameterKey=ClusterName,ParameterValue="${CLUSTER_NAME}" \
  ParameterKey=VpcId,ParameterValue="${vpc_id}" \
  ParameterKey=ProxyIgnitionLocation,ParameterValue="${PROXY_URI}" \
  ParameterKey=InfrastructureName,ParameterValue="${CLUSTER_NAME}" \
  ParameterKey=RhcosAmi,ParameterValue="${RHCOS_AMI}" \
  ParameterKey=PublicSubnet,ParameterValue="${PUBLIC_SUBNETS%%,*}\"" &

wait "$!"

aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-proxy" &
wait "$!"

# cleaning up after ourselves
aws s3 rm ${PROXY_URI}

PROXY_IP="$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-proxy" \
  --query 'Stacks[].Outputs[?OutputKey == `ProxyPublicIp`].OutputValue' --output text)"

PROXY_URL="http://${cluster_name}:${PASSWORD}@${PROXY_IP}:3128/"
# due to https://bugzilla.redhat.com/show_bug.cgi?id=1750650 we don't use a tls end point for squid

cat >> "${CONFIG}" << EOF
proxy:
  httpsProxy: ${PROXY_URL}
  httpProxy: ${PROXY_URL}
EOF
