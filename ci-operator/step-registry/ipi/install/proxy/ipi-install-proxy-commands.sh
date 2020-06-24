#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# TODO: move to image
curl -L https://github.com/mikefarah/yq/releases/download/3.3.0/yq_linux_amd64 -o /tmp/yq && chmod +x /tmp/yq

EXPIRATION_DATE=$(date -d '4 hours' --iso=minutes --utc)
TAGS="Key=expirationDate,Value=${EXPIRATION_DATE}"

CONFIG="${SHARED_DIR}/install-config.yaml"
aws_subnet="$(/tmp/yq r ${CONFIG} 'platform.aws.subnets[0]')"

region="$(/tmp/yq r ${CONFIG} 'platform.aws.region')"

INTERMEDIATE="${SHARED_DIR}/INTERMEDIATE"

CLUSTER_NAME=${NAMESPACE}-${JOB_NAME_HASH}
PASSWORD="$(cat ${INTERMEDIATE}/certs/password)"
ssh_pub_key=$(<"${CLUSTER_PROFILE_DIR}/ssh-publickey")

# get the VPC ID from the subnet -> subnet.VpcId
# describe the subnet to get vpcID -> https://docs.aws.amazon.com/goto/WebAPI/ec2-2016-11-15/DescribeSubnets
describe="$(aws ec2 describe-subnets --subnet-ids ${aws_subnet})"

vpc_id="$(echo ${describe} | jq -r .[][0].VpcId)"
subnets="$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${vpc_id})"

hosted_zones="$(aws route53 list-hosted-zones-by-vpc --vpc-id ${vpc_id} --vpc-region ${region})"

echo hosted zones: ${hosted_zones}

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
        "path": "/tmp/squid/tls.crt",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${PROXY_CERT}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/tls.key",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${PROXY_KEY}"
        },
        "mode": 420
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/ca-chain.pem",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${CA_CHAIN}"
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
      },
      {
        "filesystem": "root",
        "path": "/tmp/squid/passwd.sh",
        "user": {
          "name": "root"
        },
        "contents": {
          "source": "data:text/plain;base64,${KEY_PASSWORD}"
        },
        "mode": 493
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
  PrivateHostedZoneId:
    Description: The Route53 private zone ID to register the etcd targets with, such as Z21IXYZABCZ2A4.
    Type: String
  PrivateHostedZoneName:
    Description: The Route53 zone to register the targets with, such as cluster.example.com. Omit the trailing period.
    Type: String
  ClusterName:
    Description: The cluster name used to uniquely identify the proxy load balancer
    Type: String
  PublicSubnet:
    Description: The public subnet to launch the proxy node into.
    Type: AWS::EC2::Subnet::Id
  MasterSecurityGroupId:
    Description: The master security group ID for registering temporary rules.
    Type: AWS::EC2::SecurityGroup::Id
  VpcId:
    Description: The VPC-scoped resources will belong to this VPC.
    Type: AWS::EC2::VPC::Id
  PrivateSubnets:
    Description: The internal subnets.
    Type: List<AWS::EC2::Subnet::Id>
  ProxyIgnitionLocation:
    Default: s3://my-s3-bucket/proxy.ign
    Description: Ignition config file location.
    Type: String
  AutoRegisterDNS:
    Default: "yes"
    AllowedValues:
    - "yes"
    - "no"
    Description: Do you want to invoke DNS etcd registration, which requires Hosted Zone information?
    Type: String
  AutoRegisterELB:
    Default: "yes"
    AllowedValues:
    - "yes"
    - "no"
    Description: Do you want to invoke NLB registration, which requires a Lambda ARN parameter?
    Type: String
  RegisterNlbIpTargetsLambdaArn:
    Description: ARN for NLB IP target registration lambda.
    Type: String
  ExternalApiTargetGroupArn:
    Description: ARN for external API load balancer target group.
    Type: String
  InternalApiTargetGroupArn:
    Description: ARN for internal API load balancer target group.
    Type: String
  InternalServiceTargetGroupArn:
    Description: ARN for internal service load balancer target group.
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
      - MasterSecurityGroupId
    - Label:
        default: "Network Configuration"
      Parameters:
      - VpcId
      - AllowedProxyCidr
      - PublicSubnet
      - PrivateSubnets
      - ClusterName
    - Label:
        default: "DNS"
      Parameters:
      - AutoRegisterDNS
      - PrivateHostedZoneId
      - PrivateHostedZoneName
    - Label:
        default: "Load Balancer Automation"
      Parameters:
      - AutoRegisterELB
      - RegisterNlbIpTargetsLambdaArn
      - ExternalApiTargetGroupArn
      - InternalApiTargetGroupArn
      - InternalServiceTargetGroupArn
    ParameterLabels:
      InfrastructureName:
        default: "Infrastructure Name"
      VpcId:
        default: "VPC ID"
      AllowedProxyCidr:
        default: "Allowed ingress Source"
      PublicSubnet:
        default: "Public Subnet"
      PrivateSubnets:
        default: "Private Subnets"
      RhcosAmi:
        default: "Red Hat Enterprise Linux CoreOS AMI ID"
      ProxyIgnitionLocation:
        default: "Bootstrap Ignition Source"
      MasterSecurityGroupId:
        default: "Master Security Group ID"
      AutoRegisterDNS:
        default: "Use Provided DNS Automation"
      AutoRegisterELB:
        default: "Use Provided ELB Automation"
      PrivateHostedZoneName:
        default: "Private Hosted Zone Name"
      PrivateHostedZoneId:
        default: "Private Hosted Zone ID"
      ClusterName:
        default: "Cluster name"

Conditions:
  DoRegistration: !Equals ["yes", !Ref AutoRegisterELB]
  DoDns: !Equals ["yes", !Ref AutoRegisterDNS]

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
        ToPort: 3130
        FromPort: 3130
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
        - !Ref "MasterSecurityGroupId"
        SubnetId: !Ref "PublicSubnet"
      UserData:
        Fn::Base64: !Sub
        - '{"ignition":{"config":{"replace":{"source":"\${IgnitionLocation}","verification":{}}},"timeouts":{},"version":"2.1.0"},"networkd":{},"passwd":{},"storage":{},"systemd":{}}'
        - {
          IgnitionLocation: !Ref ProxyIgnitionLocation
        }

  ProxyRecord:
    Condition: DoDns
    Type: AWS::Route53::RecordSet
    Properties:
      HostedZoneId: !Ref PrivateHostedZoneId
      Name: !Join [".", ["squid", !Ref PrivateHostedZoneName]]
      ResourceRecords:
      - !GetAtt ProxyInstance.PublicIp
      TTL: 60
      Type: A

Outputs:
  ProxyPublicIp:
    Description: The proxy node public IP address.
    Value: !GetAtt ProxyInstance.PublicIp
EOF
}

PROXY_CERT="$(base64 -w0 ${INTERMEDIATE}/certs/intermediate.cert.pem)"
PROXY_KEY="$(base64 -w0 ${INTERMEDIATE}/private/intermediate.key.pem)"
PROXY_KEY_PASSWORD="$(cat ${ROOTCA}/intpassfile)"

HTPASSWD_CONTENTS="${CLUSTER_NAME}:"$(openssl passwd -apr1 ${PASSWORD})""
HTPASSWD_CONTENTS="$(echo -e ${HTPASSWD_CONTENTS} | base64 -w0)"

KEY_PASSWORD="$(base64 -w0 << EOF
#!/bin/sh
echo ${PROXY_KEY_PASSWORD}
EOF
)"


# define squid config
SQUID_CONFIG="$(base64 -w0 << EOF
http_port 3128
sslpassword_program /squid/passwd.sh
https_port 3130 cert=/squid/tls.crt key=/squid/tls.key cafile=/squid/ca-chain.pem
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
podman run --entrypoint='["bash", "/squid/proxy.sh"]' --expose=3128,3130 --net host --volume /tmp/squid:/squid:Z ${PROXY_IMAGE}
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
#
  ParameterKey=RhcosAmi,ParameterValue="${RHCOS_AMI}" \
  ParameterKey=PrivateHostedZoneId,ParameterValue="${PRIVATE_HOSTED_ZONE}" \
  ParameterKey=PrivateHostedZoneName,ParameterValue="${CLUSTER_NAME}.${base_domain}" \
  ParameterKey=PublicSubnet,ParameterValue="${PUBLIC_SUBNETS%%,*}\"" \
  ParameterKey=MasterSecurityGroupId,ParameterValue="${MASTER_SECURITY_GROUP}" \
  ParameterKey=PrivateSubnets,ParameterValue="${PRIVATE_SUBNETS}" \
  ParameterKey=RegisterNlbIpTargetsLambdaArn,ParameterValue="${NLB_IP_TARGETS_LAMBDA}" \
  ParameterKey=ExternalApiTargetGroupArn,ParameterValue="${EXTERNAL_API_TARGET_GROUP}" \
  ParameterKey=InternalApiTargetGroupArn,ParameterValue="${INTERNAL_API_TARGET_GROUP}" \
  ParameterKey=InternalServiceTargetGroupArn,ParameterValue="${INTERNAL_SERVICE_TARGET_GROUP}" &
wait "$!"

aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-proxy" &
wait "$!"

# cleaning up after ourselves
aws s3 rm ${PROXY_URI}

PROXY_IP="$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-proxy" \
  --query 'Stacks[].Outputs[?OutputKey == `ProxyPublicIp`].OutputValue' --output text)"

echo "Proxy is available at ${PROXY_URL}"
echo "TLS Proxy is available at ${TLS_PROXY_URL}"

echo ${PROXY_IP} > /tmp/artifacts/installer/proxyip