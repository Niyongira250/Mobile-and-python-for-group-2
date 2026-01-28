from rest_framework import serializers
from .models import User, Merchant, Product, Transaction, Notification, Menu
from .models import Order
import json

class MenuSerializer(serializers.ModelSerializer):
    productname = serializers.CharField(source='productid.productname', read_only=True)
    price = serializers.DecimalField(source='productid.price', max_digits=10, decimal_places=2, read_only=True)
    amountinstock = serializers.IntegerField(source='productid.amountinstock', read_only=True)
    category = serializers.CharField(source='productid.category', read_only=True)
    productpicture = serializers.CharField(source='productid.productpicture', read_only=True)
    
    class Meta:
        model = Menu
        fields = ['menuid', 'merchantid', 'productid', 'availability', 
                  'productname', 'price', 'amountinstock', 'category', 'productpicture']
class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = '__all__'

class MerchantSerializer(serializers.ModelSerializer):
    class Meta:
        model = Merchant
        fields = '__all__'

class ProductSerializer(serializers.ModelSerializer):
    class Meta:
        model = Product
        fields = '__all__'

class TransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Transaction
        fields = '__all__'
class NotificationSerializer(serializers.ModelSerializer):
    date = serializers.DateTimeField(format="%Y-%m-%d %H:%M:%S")
    
    class Meta:
        model = Notification
        fields = '__all__'


class OrderSerializer(serializers.ModelSerializer):
    items = serializers.JSONField()
    custom_fields = serializers.JSONField()
    
    class Meta:
        model = Order
        fields = '__all__'
    
    def to_representation(self, instance):
        """Convert JSON fields to proper format"""
        data = super().to_representation(instance)
        
        # Ensure items is a list
        if isinstance(data['items'], str):
            try:
                data['items'] = json.loads(data['items'])
            except:
                data['items'] = []
        
        # Ensure custom_fields is a dict
        if isinstance(data['custom_fields'], str):
            try:
                data['custom_fields'] = json.loads(data['custom_fields'])
            except:
                data['custom_fields'] = {}
        
        return data