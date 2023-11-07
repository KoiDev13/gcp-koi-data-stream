import random
import json

draw = round(random.uniform(0, 1), 2)
uid = f'UID0000{int(round(random.uniform(0, 5), 0))}'

# get view payload
view_item_f = open('./datalayer/view_item.json')
view_item_payload = json.load(view_item_f)

view_item_payload['user_id'] = uid

# send view
# r = requests.post(endpoint, json=view_item_payload)

print(json.dumps(view_item_payload, indent=4))