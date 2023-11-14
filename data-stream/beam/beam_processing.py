

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

cla