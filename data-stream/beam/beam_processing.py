import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.transforms import trigger
from apache_beam.io.gcp.pubsub import ReadFromPubSub
from apache_beam.io.gcp.bigquery import BigQueryDisposition, WriteToBigQuery
from apache_beam.runners import DataflowRunner

import json
import time

import config

# Define filter function

def is_item_view(event):
    """Cast event to view item flag."""
    return event['event'] == 'view_item'

def is_add_to_cart(event):
    """Cast event to add to cart flag."""
    return event['event'] == 'add_to_cart'

def is_purchase(event):
    """Cast event to purchase flag."""
    return event['event'] == 'purchase'

class ExtractValueFn(beam.DoFn):
    """Extract value from paload."""
    def process(self, element):
        print(f"ExtractValueFn: {element['ecommerce']['purchase']['value']}")
        return [element['ecommerce']['purchase']['value']]

class ExtractAndSumValue(beam.PTransform):
    """
    A transform to extract key/score information and sum the scores.
    The constructor argument `field` determines whether 'team' or 'user' info is
    extracted.
    """
    def expand(self, pcoll):
        sum_val = (
            pcoll
            | 'Map' >> beam.Map(lambda elem: (elem['user_id'], elem['ecommerce']['purchase']['value']))
            | 'SumValues' >> beam.CombinePerKey(sum)
        )
        return (sum_val)

class FormatByRow(beam.PTransform):
    """Reformating data to column name/value format."""
    def expand(self, pcoll):
        row_val = (
            pcoll
            | 'Map' >> beam.Map(lambda elem: {
                'user_id': elem[0],
                'summed_value': elem[1]
            })
        )
        return (row_val)

# Function to streaming pipeline
def streaming_pipeline(project, region):
    """
    A pipeline to streaming data from pubsub to bigquery using Dataflow.
    """

    subscription = f"projects/{project}/subscriptions/hyp_subscription_dataflow"
    bucket = f"gs://{project}-ecommerce-events/tmp_dir"

    # Set pipeline options
    options = PipelineOptions(
        streaming=True,
        project=project,
        region=region,
        staging_location="%s/staging" % bucket,
        temp_location="%s/temp" % bucket,
        subnetwork='regions/us-central1/subnetworks/terraform-network',
        service_account_email=f'retailpipeline-hyp@{project}.iam.gserviceaccount.com',
        max_num_workers=1,
    )

    # Define pipeline.
    p = beam.Pipeline(DataflowRunner(), options=options)

    # Receiving messages from PubSub and parsing json to string.
    json_message = (
        p
        | 'ReadTopic' >> ReadFromPubSub(subscription=subscription)
        | 'ParsingJson' >> beam.Map(json.loads)
    )
    
    # Extracting items views from json message.
    item_views = (
        json_message
        | 'FilterItemView' >> beam.Filter(is_item_view)
        | 'ExtractValue' >> beam.Map(lambda input: {'event_datetime': input['event_datetime'],
                                                    'event': input['event'],
                                                    'user_id': input['user_id'],
                                                    'client_id': input['client_id'],
                                                    'page': input['page'],
                                                    'page_previous': input['page_previous'],
                                                    'item_name': input['ecommerce']['items'][0]['item_name'],
                                                    'item_id': input['ecommerce']['items'][0]['item_id'],
                                                    'price': input['ecommerce']['items'][0]['price'],
                                                    'item_brand': input['ecommerce']['items'][0]['item_brand'],
                                                    'item_category': input['ecommerce']['items'][0]['item_category'],
                                                    'item_category_2': input['ecommerce']['items'][0]['item_category_2'],
                                                    'item_category_3': input['ecommerce']['items'][0]['item_category_3'],
                                                    'item_category_4': input['ecommerce']['items'][0]['item_category_4'],
                                                    'item_variant': input['ecommerce']['items'][0]['item_variant'],
                                                    'item_list_name': input['ecommerce']['items'][0]['item_list_name'],
                                                    'item_list_id' : input['ecommerce']['items'][0]['item_list_id'],
                                                    'quantity': input['ecommerce']['items'][0]['quantity']
                                                    })
    )

    fixed_windowed_items = (
        json_message
        | 'FilterPurchase' >> beam.Filter(is_purchase)
        | 'GlobalWindowing' >> beam.WindowInto(beam.window.GlobalWindows(),
                                               trigger=trigger.Repeatedly(trigger.AfterCount(10)),
                                               accumulation_mode=trigger.AccumulationMode.ACCUMULATING)
        | 'ExtractAndSum' >> ExtractAndSumValue()
        | 'FormatByRow' >> FormatByRow()
    )

    # Writing to BigQuery.
    aggregated_schema = "user_id:STRING, summed_value:FLOAT"
    aggregated_table = f"{project}:ecommerce_sink.beam_aggregated"

    fixed_windowed_items | 'WriteSumValuesToBigQuery' >> WriteToBigQuery(table=aggregated_table, schema=aggregated_schema,
                                                                create_disposition=BigQueryDisposition.CREATE_IF_NEEDED,
                                                                write_disposition=BigQueryDisposition.WRITE_APPEND)
     # Writing the PCollections to two differnt BigQuery tables.
    item_views_table = f"{project}:ecommerce_sink.beam_item_views"
    schema = "event_datetime:DATETIME, event:STRING, user_id:STRING, client_id:STRING, page:STRING, page_previous:STRING, " \
             "item_name:STRING, item_id:STRING, price:STRING, item_brand:STRING, item_category:STRING, item_category_2:STRING, item_category_3:STRING, " \
             "item_category_4:STRING, item_variant:STRING, item_list_name:STRING, item_list_id:STRING, quantity:STRING"

    item_views | "WriteItemViewsToBigQuery" >> WriteToBigQuery(table=item_views_table, schema=schema,
                                                               create_disposition=BigQueryDisposition.CREATE_IF_NEEDED,
                                                               write_disposition=BigQueryDisposition.WRITE_APPEND)

    return p.run()

if __name__ == '__main__':
    """Main program."""
    GCP_PROJECT = config.project_id
    GCP_REGION = config.location

    streaming_pipeline(project=GCP_PROJECT, region=GCP_REGION)
