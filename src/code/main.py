import argparse
from datetime import datetime, timezone
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient
import os

def main():

    key_vault_name = os.getenv("KEY_VAULT_NAME")
    managed_identity_id = os.getenv("MANAGED_IDENTITY_ID")

    print(f"KEY_VAULT_NAME={key_vault_name}")
    print(f"MANAGED_IDENTITY_ID={managed_identity_id}")

    key_vault_url = f"https://{key_vault_name}.vault.azure.net".lower()
    print(f"key_vault_url={key_vault_url}")

    CREDENTIAL = ManagedIdentityCredential(client_id=managed_identity_id)
    SECRET_CLIENT = SecretClient(vault_url=key_vault_url, credential=CREDENTIAL)
    keyvault_secret = SECRET_CLIENT.get_secret("SecretKey1", None)

    print(
        f"SecretKey1: {keyvault_secret.value}, this shows we are able to get secrets from keyvault using managed identity."
    )

    parser = argparse.ArgumentParser(
        allow_abbrev=False, description="ParallelRunJobStep Agent"
    )

    parser.add_argument("--job_input_path", type=str, default=0)
    parser.add_argument("--job_output_path", type=str, default=0)
    args, _ = parser.parse_known_args()
    OUTPUT_PATH = args.job_output_path
    INPUT_PATH = args.job_input_path

    print(f"job_output_path: %s", OUTPUT_PATH)
    print(f"job_input_path: %s", INPUT_PATH)

    # get all files in the input path
    files = os.listdir(INPUT_PATH)
    # loop through each file and process it
    for file_name in files:
        print(f"{datetime.now(timezone.utc)} Processing file: {file_name}")

        wf_path = f"{OUTPUT_PATH}/{file_name}"
        rf = open(f"{INPUT_PATH}/{file_name}", "r")
        wf = open(wf_path, "w")
        wf.write(rf.read())

if __name__ == "__main__":
    main()        