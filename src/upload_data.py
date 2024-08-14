import argparse
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from pathlib import Path
import os
from dotenv import load_dotenv

directory_path = "../data"

parser = argparse.ArgumentParser(allow_abbrev=True, description="Run upload data")
parser.add_argument("--env_path", type=str, default=0)

args, _ = parser.parse_known_args()
env_path = args.env_path

if env_path == 0:
    env_path = "./.env"

print(f"env_path: {env_path}")
dotenv_path = Path(env_path)

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
            # Upload the file
            with open(file_path, "r") as data:

                content = data.read()
                # loop 10 times
                for index in range(100):

                    # Split the filename from its extension and insert the index before the extension
                    name_parts = entry.name.rsplit(".", 1)
                    blob_name = (
                        f"{name_parts[0]}_{index}.{name_parts[1]}"
                        if len(name_parts) == 2
                        else f"{entry.name}_{index}"
                    )

                    # Get a client to interact with the specified blob (file)
                    blob_client = blob_service_client.get_blob_client(
                        container=container_name, blob=blob_name
                    )
                    blob_client.upload_blob(content, overwrite=True)
                    print(f"File {file_path} uploaded to blob storage as {blob_name}.")
