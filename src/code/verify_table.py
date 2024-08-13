import os
from azure.identity import ManagedIdentityCredential
from azure.data.tables import TableServiceClient, TableClient
from azure.core.exceptions import ResourceExistsError
def main():

    managed_identity_id = os.getenv("MANAGED_IDENTITY_ID")
    CREDENTIAL = ManagedIdentityCredential(client_id=managed_identity_id)
    storage_account_name = os.getenv("STORAGE_ACCOUNT_NAME")
    table_name = "mytesttable"

    # Construct the table service URL
    table_service_url = f"https://{storage_account_name}.table.core.windows.net"

    # Create a TableServiceClient using the managed identity credential
    table_service_client = TableServiceClient(endpoint=table_service_url, credential=CREDENTIAL)

    # Create a TableClient
    table_client = table_service_client.get_table_client(table_name=table_name)

    try:
        table_client.create_table()
        print(f"Table '{table_name}' created successfully.")
    except ResourceExistsError:
        print(f"Table '{table_name}' already exists.")

if __name__ == "__main__":
    main()