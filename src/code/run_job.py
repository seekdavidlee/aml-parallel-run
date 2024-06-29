import argparse
from datetime import datetime, timezone

def init():
    """Init."""

    global OUTPUT_PATH

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
