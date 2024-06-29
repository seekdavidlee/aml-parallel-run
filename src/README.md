# Introduction

Activate virtual environment

```bash
venv\Scripts\activate
```

Install dependencies.

```bash
pip install -r requirements.txt
```

## Stage test data

```bash
python .\upload_data.py
```

## Run an experiment

To run an experiment, you can use the `run` python script. It will schedule a pipeline to be executed in Azure Machine Learning.

```bash
python .\run.py
```