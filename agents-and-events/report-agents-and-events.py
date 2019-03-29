#!/usr/bin/python3

import logging
import re
import time

import boto3


logger = logging.getLogger()
logger.setLevel(logging.WARNING)

query = '''
SELECT useragent,
       useridentity.username,
       eventsource,
       eventname,
       errorcode,
       count(*) as "count"
FROM "default"."cloudtrail_logs_cloud_trail_test_clayton"
WHERE from_iso8601_timestamp(eventtime) > date_add('hour', -24, now())
GROUP BY useragent,
         useridentity.username,
         eventsource,
         eventname,
         errorcode
ORDER BY "count" desc;
'''.strip()


def run_query(region, bucket):
    logger.info('run in {}'.format(region))
    athena = boto3.client('athena', region_name=region)

    response = athena.start_query_execution(
        QueryString=query,
        ResultConfiguration={'OutputLocation': 's3://{}'.format(bucket)},
    )
    execution_id = response['QueryExecutionId']
    logger.info('got execution ID: {}'.format(execution_id))

    while True:
        time.sleep(5)
        response = athena.get_query_execution(QueryExecutionId=execution_id)
        state = response['QueryExecution']['Status']['State']
        logger.info('query state: {}'.format(state))
        if state == 'SUCCEEDED':
            break
        if state == 'FAILED':
            raise RuntimeError(response['QueryExecution']['Status']['StateChangeReason'])

    match = re.match('^.*/([^/]*)\.csv$', response['QueryExecution']['ResultConfiguration']['OutputLocation'])
    output_hash = match.group(1)
    logger.info('output hash: {}'.format(output_hash))
    return output_hash


def publish_results(region, bucket, output_hash):
    logger.info('publish {} in {} in {}'.format(output_hash, bucket, region))
    s3 = boto3.client('s3', region_name=region)

    source = {'Bucket': bucket, 'Key': '{}.csv'.format(output_hash)}
    s3.copy(
        CopySource=source,
        Bucket=bucket,
        Key='agents-and-events.csv',
        ExtraArgs={'ACL': 'public-read'},
    )
    logger.info('copied output to public location')

    s3.delete_object(**source)
    logger.info('deleted CSV')

    source['Key'] += '.metadata'
    s3.delete_object(**source)
    logger.info('deleted metadata')

def lambda_handler(*args, **kwargs):
    region = 'us-east-1'
    bucket = 'aws-athena-query-results-460538899914-us-east-1'

    try:
        output_hash = run_query(region=region, bucket=bucket)
        publish_results(region=region, bucket=bucket, output_hash=output_hash)
    except Exception as error:
        logger.error(error)
        raise
    else:
        logging.info('https://s3.amazonaws.com/{}/agents-and-events.csv'.format(bucket))


# not when used as a Lambda function
if __name__ == '__main__':
    lambda_handler()
