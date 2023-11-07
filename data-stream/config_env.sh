#! /bin/bash

export GCP_PROJECT="khoi-test-001-01"
export ENDPOINT_URL="<endpoint-url>" # doesn't need to be defined in the very beginning
export PUSH_ENDPOINT='<processing-endpoint-url>' # doesn't need to be defined in the very beginning
export GCP_REGION=us-central1
export RUN_PROXY_DIR=cloud-run-pubsub-proxy
export RUN_PROCESSING_DIR=processing-service
export DATAFLOW_TEMPLATE=beam
export RUN_INFERENCE_PROCESSING_SERVICE=inf_processing_service