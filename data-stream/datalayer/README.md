# Introduction of data layer  

## Type of data  

Four types of events are included:  

- add to cart  
- made purchase  
- made purcase with anomaly (artifical mistake in data to be identified later)  
- view item  

## Flow of work  

Main program: [synth_data_stream](/datalayer/synth_data_stream.py)  
Arugments: "--endpoint"  

### Steps  

- Retrive data based on condition  
- Update uid by random
- Update event time stamp based on one hour ago of current time  
- Send the post requests to endpoint (pubsub proxy)  

### Condition  

- 0 <= draw < 1/3: get view_item  
- 1/3 <= draw < 2/3: get add_to_cart  
- 2/3 <= draw < 0.95: get purchase  
- 0.95 <= draw < 1: get purchase_abnomaly  
