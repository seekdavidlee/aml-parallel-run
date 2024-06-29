# Introduction

Navigate to src directory.

Create a virtual environment

```bash
python -m venv venv
```

Activate virtual environment

```bash
venv\Scripts\activate
```

Install dependencies.

```bash
pip install -r requirements.txt
```

## Run an experiment

To run an experiment, you can use the `run.py` python script. It will schedule a pipeline to be executed in Azure Machine Learning.

```bash
python .\run.py
```

You will need to create a `.env` environment file first. This defines the parameters for the experiment.

```env

```

By default, the script will look for a `.env` file. However, you can create multiple environment files and use the `--env_path` argument to specify a different environment file to use.

* AML_COMPUTE - Use `local` to run locally or a existing compute such as `compute` to run on the cloud.
