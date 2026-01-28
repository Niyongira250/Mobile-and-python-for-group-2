from django.db import models


class User(models.Model):
    userid = models.AutoField(primary_key=True)
    nationalid = models.CharField(max_length=20)
    paycode = models.CharField(max_length=20)
    profilepicture = models.ImageField(upload_to='profile_pics/', null=True, blank=True)
    accounttype = models.CharField(max_length=10)
    email = models.EmailField()
    username = models.CharField(max_length=50)
    phonenumber = models.CharField(max_length=20)
    password = models.CharField(max_length=255)
    dateofbirth = models.DateField(null=True)
    balance = models.DecimalField(max_digits=10, decimal_places=2, default=5000.00)
    pin = models.CharField(max_length=6, default='123456')  # PIN column added

    class Meta:
        managed = False
        db_table = 'user'
        
    def __str__(self):
        return f"{self.username} (User)"


class Merchant(models.Model):
    merchantid = models.AutoField(primary_key=True)
    nationalid = models.CharField(max_length=20)
    merchantpaycode = models.CharField(max_length=20)
    profilepicture = models.ImageField(upload_to='profile_pics/', null=True, blank=True)
    businesstype = models.CharField(max_length=100)
    accounttype = models.CharField(max_length=10)
    email = models.EmailField()
    username = models.CharField(max_length=50)
    phonenumber = models.CharField(max_length=20)
    password = models.CharField(max_length=255)
    dateofcreation = models.DateField(null=True)
    balance = models.DecimalField(max_digits=10, decimal_places=2, default=5000.00)
    pin = models.CharField(max_length=6, default='123456')  # PIN column added

    class Meta:
        managed = False
        db_table = 'merchant'
        
    def __str__(self):
        return f"{self.username} (Merchant)"


class Notification(models.Model):
    notificationid = models.AutoField(primary_key=True)
    title = models.CharField(max_length=100)
    content = models.TextField()
    urgency = models.CharField(max_length=10, choices=[('low', 'Low'), ('medium', 'Medium'), ('high', 'High')])
    designated_to = models.CharField(max_length=10, choices=[('user', 'User'), ('merchant', 'Merchant'), ('all', 'All')])
    date = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        db_table = 'notification'

    def __str__(self):
        return self.title


class Transaction(models.Model):
    transactionid = models.BigIntegerField(primary_key=True)
    date = models.DateTimeField(auto_now_add=True)  # Changed to auto_now_add
    transfertype = models.CharField(max_length=50, default='Normal transfer')
    receiverid = models.IntegerField()
    senderid = models.IntegerField()
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    charge = models.DecimalField(max_digits=12, decimal_places=2, default=20.00)
    status = models.CharField(max_length=10, default='success')
    # Add these fields to track account types
    sender_type = models.CharField(max_length=10, choices=[('user', 'User'), ('merchant', 'Merchant')], default='user')
    receiver_type = models.CharField(max_length=10, choices=[('user', 'User'), ('merchant', 'Merchant')], default='user')

    class Meta:
        managed = False
        db_table = 'transaction'
        
    def __str__(self):
        return f"Transaction {self.transactionid}: {self.senderid} -> {self.receiverid} ({self.amount})"
    
    def get_sender_name(self):
        """Get sender name based on sender_type"""
        try:
            if self.sender_type == 'user':
                sender = User.objects.get(userid=self.senderid)
                return sender.username
            else:
                sender = Merchant.objects.get(merchantid=self.senderid)
                return sender.username
        except (User.DoesNotExist, Merchant.DoesNotExist):
            return f"Unknown {self.sender_type}"
    
    def get_receiver_name(self):
        """Get receiver name based on receiver_type"""
        try:
            if self.receiver_type == 'user':
                receiver = User.objects.get(userid=self.receiverid)
                return receiver.username
            else:
                receiver = Merchant.objects.get(merchantid=self.receiverid)
                return receiver.username
        except (User.DoesNotExist, Merchant.DoesNotExist):
            return f"Unknown {self.receiver_type}"


class Product(models.Model):
    productid = models.BigIntegerField(primary_key=True)
    productname = models.CharField(max_length=100)
    productpicture = models.CharField(max_length=255)
    amountinstock = models.IntegerField()
    price = models.DecimalField(max_digits=10, decimal_places=2)
    category = models.CharField(max_length=50)
    merchantid = models.IntegerField()

    class Meta:
        managed = False
        db_table = 'product'
        
    def __str__(self):
        return self.productname


class Menu(models.Model):
    menuid = models.AutoField(primary_key=True)
    merchantid = models.IntegerField()
    productid = models.BigIntegerField()
    availability = models.BooleanField()

    class Meta:
        managed = False
        db_table = 'menu'


class ExtraMenu(models.Model):
    id = models.AutoField(primary_key=True)
    merchantid = models.IntegerField()
    fieldname = models.CharField(max_length=100)

    class Meta:
        managed = False
        db_table = 'etramenu'


class Sales(models.Model):
    saleid = models.AutoField(primary_key=True)
    merchantid = models.IntegerField()
    productname = models.CharField(max_length=100)
    date = models.DateTimeField(auto_now_add=True)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    quantity = models.IntegerField()

    class Meta:
        managed = False
        db_table = 'sales'

from django.db import models
import json

class Order(models.Model):
    orderid = models.BigIntegerField(primary_key=True)
    order_number = models.CharField(max_length=20, unique=True)
    customer_id = models.IntegerField()
    customer_type = models.CharField(max_length=10, choices=[('user', 'User'), ('merchant', 'Merchant')])
    customer_name = models.CharField(max_length=100)
    merchant_id = models.IntegerField()
    merchant_name = models.CharField(max_length=100)
    table_name = models.CharField(max_length=50, blank=True, null=True)
    items = models.JSONField()
    custom_fields = models.JSONField(default=dict, blank=True)
    total_amount = models.DecimalField(max_digits=12, decimal_places=2)
    status = models.CharField(max_length=20, choices=[
        ('pending', 'Pending'),
        ('confirmed', 'Confirmed'),
        ('preparing', 'Preparing'),
        ('ready', 'Ready for Pickup'),
        ('delivered', 'Delivered'),
        ('cancelled', 'Cancelled')
    ], default='pending')
    
    # New payment fields
    is_paid = models.BooleanField(default=False)
    payment_date = models.DateTimeField(null=True, blank=True)
    transaction_id = models.BigIntegerField(null=True, blank=True)
    tip_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    customer_message = models.TextField(blank=True, null=True)
    merchant_paycode = models.CharField(max_length=20, blank=True, null=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        managed = False
        db_table = 'orders'
        indexes = [
            models.Index(fields=['customer_id', 'customer_type']),
            models.Index(fields=['merchant_id']),
            models.Index(fields=['status']),
            models.Index(fields=['is_paid']),
            models.Index(fields=['payment_date']),
            models.Index(fields=['created_at']),
            models.Index(fields=['transaction_id']),
        ]
        
    def __str__(self):
        return f"Order #{self.order_number} - {self.customer_name} to {self.merchant_name}"
    
    def get_items_list(self):
        """Parse items JSON and return as list"""
        try:
            if isinstance(self.items, str):
                return json.loads(self.items)
            return self.items
        except:
            return []
    
    def get_custom_fields_dict(self):
        """Parse custom fields JSON and return as dict"""
        try:
            if isinstance(self.custom_fields, str):
                return json.loads(self.custom_fields)
            return self.custom_fields
        except:
            return {}