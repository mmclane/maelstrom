#!/home/jmeter/venv/bin/python3
import logging
import time
import subprocess
import json
import paramiko

from azure.storage.blob import BlockBlobService
from azure.storage.queue import QueueService

# For Summary phase
import pandas as pd
import argparse


TEST_GUID="${uuid}"
SA_CONN_STRING="${conn_string}"
SLAVE_IPS=${slave_ips_array}
MASTER_PRIVATE_IP="${master_priv_ip}"
SA_CONTAINER_NAME="testresults"
APP_QUEUE="appmessagequeue"
TEST_QUEUE="test-" + TEST_GUID

LOG_FILE='/tmp/bootstrap.log'
logging.basicConfig(filename=LOG_FILE,level=logging.DEBUG, format='%(asctime)s %(levelname)s:%(message)s')

MAELSTROM_URL='https://cbsdevops-maelstrom.par.preprod.crto.in'
MAX_SERVICE_ATTEMPTS=120
MAX_SSH_ATTEMPTS=40

QUEUE_SERVICE = QueueService(connection_string=SA_CONN_STRING)
BLOB_SERVICE = BlobService(connection_string=SA_CONN_STRING)


NUMERIC_COLUMNS = [
        'elapsed',
        'bytes',
        'sentBytes',
        'Latency',
        'IdleTime',
        'Connect'
        ]


def transform_dict(input_dict):
    target = {}
    for col in NUMERIC_COLUMNS:
        target[col] = []
        for time in input_dict[col]:
            target[col].append((time.to_pydatetime().isoformat(),input_dict[col][time]))

    return target


def summarize_file(input_file, output_file):
    results = pd.read_csv(input_file, index_col='timeStamp')
    results.index = pd.to_datetime(results.index, unit='ms')
    averages = results.resample('T').mean().to_dict()
    maximums = results.resample('T').max().to_dict()
    minimums = results.resample('T').min().to_dict()

    output = {}
    output['averages'] = transform_dict(averages)
    output['maximums'] = transform_dict(maximums)
    output['minimums'] = transform_dict(minimums)

    with open(output_file, 'w') as outfile:
        json.dump(output, outfile)


class MaelstromException(Exception):
    pass


def remote_command(ip_address, command):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.client.AutoAddPolicy)
    client.load_system_host_keys()
    client.connect(username='jmeter',hostname=ip_address,key_filename='/home/jmeter/.ssh/id_rsa')
    stdin, stdout, stderr = client.exec_command(command)
    output = stdout.channel.recv_exit_status()
    client.close()
    return output


def push_remote_file(ip_address,local_file,remote_file):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.client.AutoAddPolicy)
    ssh.load_system_host_keys()
    ssh.connect(username='jmeter',hostname=ip_address,key_filename='/home/jmeter/.ssh/id_rsa')
    sftp = ssh.open_sftp()
    sftp.put(local_file, remote_file)
    sftp.close()
    ssh.close()


def run_command(*args):
    """This acts as a wrapper for subprocess so that it can be easily mocked allowing for easy testing.
    It also allows for there to be customizations in the calling of subprocess across the application.
    """
    return subprocess.run(args)


def post_test_status(status):
    queue_message = { "id": TEST_GUID, "status": status }
    QUEUE_SERVICE.put_message(APP_QUEUE,json.dumps(queue_message))


def failure(message, tries):
    post_test_status("failure")

    message = "{} failed to start the jmeter-daemon service after {} attempts.".format(message, tries)
    logging.error(message)

    BLOB_SERVICE.create_blob_from_path(SA_CONTAINER_NAME,"load_tests/{}/failure".format(TEST_GUID),LOG_FILE)

    raise Exception(message)


def add_to_known_hosts(ip_address):
    run_command('sudo', '-u', 'jmeter', 'ssh-keyscan', ip_address, '>>', '/home/jmeter/.ssh/known_hosts')
    run_command('sudo', 'chown', 'jmeter:jmeter', '/home/jmeter/.ssh/known_hosts')


def checkService(ip_address, state):
    attempts = 0
    delay=5

    add_to_known_hosts(ip_address)

    while True:
        complete_process = run_command(
            'sudo', '-u', 'jmeter', 'ssh', 'jmeter@' + ip_address,
            "\"systemctl is-active jmeter-daemon | grep {}\"".format(state))
        if complete_process.returncode == 0:
            logging.info("Server with IP:{} ready.".format(ip_address))
            break
        else:
            logging.info("Server with IP:{} not ready.".format(ip_address))
            time.sleep(delay)
        attempts += 1

        if attempts > MAX_SERVICE_ATTEMPTS:
            failure(ip_address, attempts)


def retry_scp(ip_address, file_to_copy):
    attempts = 0
    delay=15

    add_to_known_hosts(ip_address)

    while True:
        complete_command = run_command('sudo', '-u', 'jmeter', 'scp', file_to_copy, ip_address + ':')
        if complete_command.returncode == 0:
            break
        else:
            attempts += 1
            if attempts < MAX_SSH_ATTEMPTS:
                logging.warn("Failed to initialize {}: try {}".format(ip_address, attempts))
                time.sleep(delay)
            else:
                failure(ip_address,attempts)


def retry_ssh_tunnel(ip_address):
    attempts = 0
    delay = 15
    logging.info("Setup ssh tunnel {}".format(ip_address))
    run_command('sudo', '-u', 'jmeter', 'ssh-keyscan', ip_address, '>>', '/home/jmeter/.ssh/known_hosts')
    run_command('chown', 'jmeter:jmeter', '/home/jmeter/.ssh/known_hosts')
    while True:
        completed_command = run_command('sudo', '-u', 'jmeter', 'ssh', '-R', '5001:localhost:5001', '-N', '-f', ip_address)
        if completed_command.returncode == 0:
            break
        else:
            attempts += 1
            if attempts < MAX_SSH_ATTEMPTS:
                logging.warn("Failed tunnel for {}: try {}".format(ip_address, attempts))
                time.sleep(delay)
            else:
                failure(ip_address, attempts)


def update_slave_keystore(ip_address):
  logging.info("Updating {}".format(ip_address))
  jks_store_file = '/usr/local/lib/jmeter/apache-jmeter-4.0/bin/rmi_keystore.jks'
  push_remote_file(ip_address, jks_store_file, 'rmi_keystore.jks')
  remote_command(ip_address,"sudo /usr/local/sbin/update_keystore.sh /home/jmeter/rmi_keystore.jks")


def wait_for_node_ready():
    attempts = 0
    delay=15

    while True:
        # If we go over 32 messages then we should consider getting more requests out of our servers.
        messages = QUEUE_SERVICE.peek_messages(TEST_QUEUE, num_messages=32)

        if len(messages) == len(SLAVE_IPS):
            break
        attempts += 1
        if attempts > MAX_SSH_ATTEMPTS:
            failure("Cluster failed to come online", attempts)
        time.sleep(delay)


def download_test_data():
    BLOB_SERVICE.get_blob_to_path(SA_CONTAINER_NAME,"load_tests/{}/loadtest.jmx".format(TEST_GUID),'/home/jmeter/loadtest.jmx')
    BLOB_SERVICE.get_blob_to_path(SA_CONTAINER_NAME,"load_tests/{}/routes.csv".format(TEST_GUID),'/home/jmeter/routes.csv')
    run_command('chown', 'jmeter:jmeter', '/home/jmeter/loadtest.jmx')
    run_command('chown', 'jmeter:jmeter', '/home/jmeter/routes.csv')

    run_command('echo', SA_CONN_STRING, '>', '/opt/lots_storage_conn_str')
    run_command('echo', TEST_GUID, '>', '/opt/lots_run_uuid')
    run_command('echo', '\n'.join(SLAVE_IPS), '>', '/opt/lots_slave_ips')


def run_jmeter():
    post_test_status("running")

    run_command('sudo', '-u', 'jmeter', 'mkdir', '-p', '/home/jmeter/jmeterlogs')
    run_command('sudo', '-u', 'jmeter', 'jmeter', '-n',
            '-Djava.rmi.server.hostname=' + MASTER_PRIVATE_IP,
            '-t', '/home/jmeter/loadtest.jmx',
            '-R' + ",".join(SLAVE_IPS),
            '-l', '/home/jmeter/results.csv',
            '-j', '/home/jmeter/jmeterlogs/jmeter.log')
    logging.info("Creating results...")
    run_command('sudo', '-u', 'jmeter', 'mkdir', '-p', '/home/jmeter/summary')
    run_command('sudo', 'jmeter',
            '-g', '/home/jmeter/results.csv',
            '-o', '/home/jmeter/summary',
            '-j', '/home/jmeter/jmeterlogs/jmeter-results.log')


def upload_test_results():
    BLOB_SERVICE.create_blob_from_path(SA_CONTAINER_NAME,"load_tests/{}/results.csv".format(TEST_GUID),'/home/jmeter/results.csv')
    BLOB_SERVICE.create_blob_from_path(SA_CONTAINER_NAME,"load_tests/{}/aggregate.json".format(TEST_GUID),'/home/jmeter/aggregate.json')

    run_command('sudo','-u', 'jmeter', 'tar',
            '-C', '/home/jmeter/',
            '-cvzf', '/home/jmeter/results.tar.gz',
            'summary', 'results.csv')

    BLOB_SERVICE.create_blob_from_path(SA_CONTAINER_NAME,"load_tests/{}/results.tar.gz".format(TEST_GUID),'/home/jmeter/results.tar.gz')


def main():
    try:
        run_command('sudo', 'systemctl', 'disable', 'firewalld')
        run_command('sudo', 'systemctl', 'stop', 'firewalld')

        # For now I am just going to wrap this with the new ui integration checks we can remove the other
        # checks at a later date
        # TODO: Update script to remove other checks that we were using to determine when to proceed
        wait_for_node_ready()

        logging.info("Testing slave connectivity:")
        for ip in SLAVE_IPS:
            checkService(ip,"[unknown|failed]")

        logging.info("Bootstrap keystore")
        # TODO: Translate to python
        run_command('sudo', '/usr/local/bin/bootstrap_ssl.sh')
        logging.info("Keystore success")

        for ip in SLAVE_IPS:
            retry_ssh_tunnel(ip)

        # Sync down files and then move them into place
        logging.info("Downloading test data.")
        download_test_data()

        for ip in SLAVE_IPS:
            retry_scp(ip, '/home/jmeter/routes.csv')
            update_slave_keystore(ip)
            checkService(ip, 'active')

        logging.info("Running test...")
        time.sleep(60)  # just give everything a minute to settle out
        run_jmeter()

        logging.info("Summarizing results...")
        summarize_file('/home/jmeter/results.csv', '/home/jmeter/aggregate.json')

        logging.info("Uploading results...")
        upload_test_results()

        logging.info("Test finished.")
        post_test_status("complete")

    except MaelstromException as m:
        pass # This is because a failure message has already been sent.
    except Exception as e:
        failure('Failure somewhere:' + str(e), 1)

if __name__ == "__main__":
    main()
