import os
from azure.identity import ManagedIdentityCredential
from azure.storage.queue import QueueServiceClient
from azure.core.exceptions import ResourceExistsError
def main():

    managed_identity_id = os.getenv("MANAGED_IDENTITY_ID")
    CREDENTIAL = ManagedIdentityCredential(client_id=managed_identity_id)
    storage_account_name = os.getenv("STORAGE_ACCOUNT_NAME")
    queue_name = "mytestqueue"
    
    queue_service_url = f"https://{storage_account_name}.queue.core.windows.net"
    queue_service_client = QueueServiceClient(account_url=queue_service_url, credential=CREDENTIAL)

    try:
        queue_client = queue_service_client.create_queue(queue_name)
        print(f"Queue '{queue_name}' created successfully.")
    except ResourceExistsError:
        print(f"Queue '{queue_name}' already exists.")

if __name__ == "__main__":
    main()