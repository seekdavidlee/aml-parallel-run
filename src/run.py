from datetime import datetime
import os
from azure.ai.ml.parallel import parallel_run_function, RunFunction
from dotenv import load_dotenv
from pathlib import Path
from azure.ai.ml import MLClient, Input, Output
from azure.identity import DefaultAzureCredential
from azure.ai.ml.constants import AssetTypes
from azure.ai.ml.entities import Environment
from azure.ai.ml.dsl import pipeline
import argparse

parser = argparse.ArgumentParser(allow_abbrev=True, description="Run pipeline")
parser.add_argument("--env_path", type=str, default=0)

args, _ = parser.parse_known_args()
env_path = args.env_path

if env_path == 0:
    env_path = "./.env"

print(f"env_path: {env_path}")
dotenv_path = Path(env_path)
load_dotenv(dotenv_path=dotenv_path, override=True)

aml_subscription_id = os.getenv("AML_SUBSCRIPTION_ID")
aml_resource_group_name = os.getenv("AML_RESOURCE_GROUP_NAME")
aml_workspace_name = os.getenv("AML_WORKSPACE_NAME")
aml_compute_name = os.getenv("AML_COMPUTE_NAME")

aml_log_level = os.getenv("AML_LOG_LEVEL")
aml_image_name = os.getenv("AML_IMAGE_NAME")
aml_experiment_name = os.getenv("AML_EXPERIMENT_NAME")
aml_experiment_name = aml_experiment_name.replace(" ", "_").lower()
if aml_log_level is None:
    aml_log_level = "INFO"

print(f"aml_subscription_id={aml_subscription_id}")
print(f"aml_resource_group_name={aml_resource_group_name}")
print(f"aml_workspace_name={aml_workspace_name}")
print(f"aml_compute_name={aml_compute_name}")

print(f"aml_log_level={aml_log_level}")
print(f"aml_image_name={aml_image_name}")
print(f"aml_experiment_name={aml_experiment_name}")

aml_job_concurrency = int(os.getenv("AML_JOB_CONCURRENCY"))
aml_job_instance_count = int(os.getenv("AML_JOB_INSTANCE_COUNT"))
aml_job_input_datastore = os.getenv("AML_JOB_INPUT_DATASTORE")
aml_job_output_datastore = os.getenv("AML_JOB_OUTPUT_DATASTORE")

print(f"aml_job_concurrency={aml_job_concurrency}")
print(f"aml_job_instance_count={aml_job_instance_count}")
print(f"aml_job_input_datastore={aml_job_input_datastore}")
print(f"aml_job_output_datastore={aml_job_output_datastore}")

job_key_vault_name = os.getenv("JOB_KEY_VAULT_NAME")
managed_identity_id = os.getenv("JOB_MANAGED_IDENTITY_ID")
print(f"job_key_vault_name={job_key_vault_name}")
print(f"managed_identity_id={managed_identity_id}")

default_credential = DefaultAzureCredential(exclude_shared_token_cache_credential=True)

# connect to the workspace
ml_client = MLClient(
    default_credential,
    subscription_id=aml_subscription_id,
    resource_group_name=aml_resource_group_name,
    workspace_name=aml_workspace_name,
)

# set up pytorch environment
env = Environment(
    image=aml_image_name,
    conda_file="environments/parallel.yml",
    name="pytorch-env",
)

timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
job_input_path = f"azureml://datastores/{aml_job_input_datastore}/paths/"
job_output_path_1 = (
    f"azureml://datastores/{aml_job_output_datastore}/paths/{timestamp}/job_1"
)
job_output_path_2 = (
    f"azureml://datastores/{aml_job_output_datastore}/paths/{timestamp}/job_2"
)
job_suffix = f"{aml_experiment_name}_{timestamp}"

batch_job1 = parallel_run_function(
    name=f"batch_job1_{job_suffix}",
    display_name="Batch job 1 with sample Dataset as input",
    description="parallel component for batch job 1",
    inputs=dict(
        job_data_path=Input(
            type=AssetTypes.URI_FOLDER,
            mode="download",
            path=job_input_path,
            description="Files to be processed.",
        ),
    ),
    outputs=dict(
        job_output_path=Output(
            type=AssetTypes.URI_FOLDER,
            mode="upload",
            path=job_output_path_1,
        ),
    ),
    input_data="${{inputs.job_data_path}}",
    instance_count=aml_job_instance_count,
    max_concurrency_per_instance=aml_job_concurrency,
    mini_batch_size="1",
    mini_batch_error_threshold=1,
    retry_settings=dict(max_retries=3, timeout=60),
    logging_level=aml_log_level,
    is_deterministic=False,
    environment_variables=dict(
        KEY_VAULT_NAME=job_key_vault_name, MANAGED_IDENTITY_ID=managed_identity_id
    ),
    task=RunFunction(
        code="code",
        entry_script="run_job.py",
        program_arguments="--job_output_path ${{outputs.job_output_path}} "
        "--resource_monitor_interval 0",
        environment=env,
    ),
)

batch_job2 = parallel_run_function(
    name=f"batch_job2_{job_suffix}",
    display_name="Batch job 2 with Job 2 Output as input",
    description="parallel component for batch job 2",
    inputs=dict(
        job_data_path=Input(
            type=AssetTypes.URI_FOLDER,
            mode="download",
            path=job_input_path,
            description="Files to be processed.",
        ),
    ),
    outputs=dict(
        job_output_path=Output(
            type=AssetTypes.URI_FOLDER,
            mode="upload",
            path=job_output_path_2,
        ),
    ),
    input_data="${{inputs.job_data_path}}",
    instance_count=aml_job_instance_count,
    max_concurrency_per_instance=aml_job_concurrency,
    mini_batch_size="1",
    mini_batch_error_threshold=1,
    retry_settings=dict(max_retries=3, timeout=60),
    logging_level=aml_log_level,
    is_deterministic=False,
    environment_variables=dict(
        KEY_VAULT_NAME=job_key_vault_name, MANAGED_IDENTITY_ID=managed_identity_id
    ),
    task=RunFunction(
        code="code",
        entry_script="run_job.py",
        program_arguments="--job_output_path ${{outputs.job_output_path}} "
        "--resource_monitor_interval 0",
        environment=env,
    ),
)


@pipeline(name=timestamp, display_name=f"Job {timestamp}")
def parallel_in_pipeline():

    batch_job1_with_file_data = batch_job1()
    batch_job2_with_file_data = batch_job2(
        job_data_path=batch_job1_with_file_data.outputs.job_output_path,
    )

    return {
        "pipeline_job1_out_job_result": batch_job1_with_file_data.outputs.job_output_path,
        "pipeline_job2_out_job_result": batch_job2_with_file_data.outputs.job_output_path,
    }


# create a pipeline
pipeline_job = parallel_in_pipeline()

# set pipeline level compute
pipeline_job.settings.default_compute = aml_compute_name

# create a pipeline
pipeline_job = ml_client.jobs.create_or_update(
    pipeline_job,
    experiment_name=aml_experiment_name,
)

# This is the timestamp reference for the pipeline, user should take this reference to monitor the pipeline
print(f"Pipeline created: {timestamp}, see: {pipeline_job.studio_url}")
