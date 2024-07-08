import boto3
import json

def lambda_handler(event, context):
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('VisitorCount')

    response = table.update_item(
        Key={'id': 'siteCounter'},
        UpdateExpression='ADD visitCount :inc',
        ExpressionAttributeValues={':inc': 1},
        ReturnValues="UPDATED_NEW"
    )

    return {
        'statusCode': 200,
        'body': json.dumps(f"Visitor Count: {response['Attributes']['visitCount']}")
    }