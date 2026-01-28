import random
import datetime

def generate_user_paycode():
    return "UP" + str(random.randint(100000, 999999))

def generate_merchant_paycode():
    year = datetime.datetime.now().year
    return f"MP{year}{random.randint(1000, 9999)}"
