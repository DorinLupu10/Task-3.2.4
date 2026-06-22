import json
import urllib.request
import urllib.error
import os

def lambda_handler(event, context):
    discord_webhook_url = os.environ['DISCORD_WEBHOOK_URL'].strip()
    
    for record in event['Records']:
        sns_message = json.loads(record['Sns']['Message'])
        
        alarm_name = sns_message.get('AlarmName', 'Unknown')
        new_state = sns_message.get('NewStateValue', 'Unknown')
        reason = sns_message.get('NewStateReason', '')
        
        
        message = {
            "content": f" **AWS Alert: {alarm_name}**\nState: {new_state}\nReason: {reason}"
        }
        
        data = json.dumps(message).encode('utf-8')
        req = urllib.request.Request(
            discord_webhook_url,
            data=data,
            headers={
                'Content-Type': 'application/json',
                'User-Agent': 'Mozilla/5.0'
            },
            method='POST'
        )
        urllib.request.urlopen(req)
    
    return {'statusCode': 200}