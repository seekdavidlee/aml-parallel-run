from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from pathlib import Path
import os
from dotenv import load_dotenv

directory_path = "../data"

dotenv_path = Path("./.env")
load_dotenv(dotenv_path=dotenv_path, override=True)
container_name = os.getenv("UPLOAD_CONTAINER_NAME")
storage_url = os.getenv("UPLOAD_STORAGE_URL")

print(f"UPLOAD_CONTAINER_NAME={container_name}")
print(f"UPLOAD_STORAGE_URL={storage_url}")

default_credential = DefaultAzureCredential(exclude_shared_token_cache_credential=True)
blob_service_client = BlobServiceClient(
    account_url=storage_url, credential=default_credential
)

# Get a client to interact with the specified container
container_client = blob_service_client.get_container_client(container_name)


# Iterate over files in directory_path
with os.scandir(directory_path) as entries:
    for entry in entries:
        if entry.is_file():
            file_path = entry.path
            blob_name = entry.name
            # Upload the file
            with open(file_path, "rb") as data:
                # Get a client to interact with the specified blob (file)
                blob_client = blob_service_client.get_blob_client(
                    container=container_name, blob=blob_name
                )
                blob_client.upload_blob(data, overwrite=True)
                print(f"File {file_path} uploaded to blob storage as {blob_name}.")
