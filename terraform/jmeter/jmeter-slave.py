#!/home/jmeter/venv/bin/python3
import uuid
import time
import subprocess
import json

from azure.storage.queue import QueueService

TEST_GUID="${uuid}"
SA_CONN_STRING="${conn_string}"
TEST_QUEUE="test-" + TEST_GUID
# TODO: Transition this from preprod to prod after demo
MAELSTROM_URL="https://cbsdevops-maelstrom.par.preprod.crto.in"

QUEUE_SERVICE = QueueService(connection_string=SA_CONN_STRING)


def main():
    subprocess.run(['sudo', 'systemctl', 'disable', 'firewalld'])
    subprocess.run(['sudo', 'systemctl', 'stop', 'firewalld'])
    time.sleep(20)
    node_uuid = uuid.uuid1()

    queue_message = {
        "guid": str(node_uuid),
        "status": "success"
    }

    QUEUE_SERVICE.put_message(TEST_QUEUE,json.dumps(queue_message))


if __name__ == "__main__":
    main()
