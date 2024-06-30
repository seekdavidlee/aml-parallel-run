import argparse
from datetime import datetime, timezone
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient
import os


def init():
    """Init."""

    global OUTPUT_PATH

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
    parser.add_argument("--job_output_path", type=str, default=0)
    args, _ = parser.parse_known_args()
    OUTPUT_PATH = args.job_output_path

    print(f"job_output_path: %s", OUTPUT_PATH)

    print("init done")


def run(mini_batch):
    """Run."""

    print("running job")

    try:
        for entry in mini_batch:
            print(f"{datetime.now(timezone.utc)} Processing file: {entry}")
            file_name = entry.split("/")[-1]
            wf_path = f"{OUTPUT_PATH}/{file_name}"
            rf = open(entry, "r")
            wf = open(wf_path, "w")
            wf.write(rf.read())

        print("job completed")

    except Exception as e:
        print(f"Failed to run job: {e}")
        raise e

    return mini_batch
