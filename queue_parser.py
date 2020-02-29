import json
import sys
import requests

filepath = "rabbitmq_log_" + str(sys.argv[2]) + ".txt"

file = open(filepath,"r")
queueProperties = file.read()

#print queueProperties

influx_url = 'http://localhost:8086/write?db=InfluxDB'

queuePropertiesJSON = json.loads(queueProperties)

for singleQueueProperties in queuePropertiesJSON:
	if singleQueueProperties["name"] == str(sys.argv[1]):
		#print singleQueueProperties["name"]
		data_string = singleQueueProperties["name"] + ",hostname=" + str(sys.argv[2]) + ",state=" + singleQueueProperties["state"] + " " + "messageCount=" + str(singleQueueProperties["messageCount"]) + ",consumerCount=" + str(singleQueueProperties["consumerCount"])
		r = requests.post(influx_url, data=data_string)
	
		if singleQueueProperties["state"] == "OK":
				sys.exit(0)
		elif singleQueueProperties["state"] == "WARNING":
				sys.exit(1)
		elif singleQueueProperties["state"] == "CRITICAL":
				sys.exit(2)
		elif singleQueueProperties["state"] == "NOTFOUND":
				sys.exit(3)
	else :
		sys.exit(3)
