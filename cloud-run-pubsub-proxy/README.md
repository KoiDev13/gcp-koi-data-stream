# Introduction of proxy app  

This code is a Node.js application that uses the Express.js framework to create a web server.  
It defines two routes for handling HTTP requests: a GET route at the root path ("/") and a POST route at "/json."  
Cloud Run Proxy is a express webserver that listenes to incoming requests and publishes them to a chosen Pub/Sub topic.  

## Run command  

```bash
docker build -t gcr.io/$GCP_PROJECT/pubsub-proxy $RUN_PROXY_DIR
```
