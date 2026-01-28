from django.shortcuts import render, get_object_or_404
from django.http import JsonResponse
from .models import User, Merchant, Order
from django.views.decorators.csrf import csrf_exempt
import json
import logging

logger = logging.getLogger(__name__)

@csrf_exempt
def admin_dashboard(request):
    """Single comprehensive admin dashboard with all data"""
    try:
        # Get all data from database
        users = User.objects.all()
        merchants = Merchant.objects.all()
        orders = Order.objects.all()
        services = ExtraMenu.objects.all()
        products = Product.objects.all()
        transactions = Transaction.objects.all()
        menus = Menu.objects.all()
        
        # Get counts for analytics
        total_users = users.count()
        total_merchants = merchants.count()
        total_orders = orders.count()
        total_products = products.count()
        total_transactions = transactions.count()
        total_services = services.count()
        
        # Today's stats
        today = datetime.now().date()
        orders_today = Order.objects.filter(created_at__date=today).count()
        
        # Revenue calculations
        total_revenue = Transaction.objects.aggregate(total=Sum('amount'))['total'] or 0
        revenue_today = Transaction.objects.filter(date__date=today).aggregate(total=Sum('amount'))['total'] or 0
        
        context = {
            # All data for tables
            'users': users,
            'merchants': merchants,
            'orders': orders,
            'services': services,
            'products': products,
            'transactions': transactions,
            'menus': menus,
            
            # Analytics counts
            'users_count': total_users,
            'merchants_count': total_merchants,
            'orders_count': total_orders,
            'products_count': total_products,
            'transactions_count': total_transactions,
            'services_count': total_services,
            
            # Additional stats
            'orders_today': orders_today,
            'total_revenue': total_revenue,
            'revenue_today': revenue_today,
            'today': today,
        }
        
        return render(request, 'api/admin_dashboard.html', context)
        
    except Exception as e:
        print(f"Error in admin_dashboard: {str(e)}")
        import traceback
        traceback.print_exc()
        # Return empty context if there's an error
        return render(request, 'api/admin_dashboard.html', {
            'users': [],
            'merchants': [],
            'orders': [],
            'services': [],
            'products': [],
            'transactions': [],
            'menus': [],
            'users_count': 0,
            'merchants_count': 0,
            'orders_count': 0,
            'products_count': 0,
            'transactions_count': 0,
            'services_count': 0,
            'error': str(e)
        })
@csrf_exempt
def search_by_paycode(request):
    if request.method == "GET":
        paycode = request.GET.get('paycode', None)
        if paycode:
            user = User.objects.filter(paycode=paycode).first()
            if user:
                return JsonResponse({"status": "success", "user": {
                    "id": user.id,
                    "name": user.name,
                    "email": user.email,
                    "paycode": user.paycode
                }})
            else:
                return JsonResponse({"status": "error", "message": "User not found"})
        return JsonResponse({"status": "error", "message": "Paycode not provided"})

@csrf_exempt
def create_entry(request):
    if request.method == "POST":
        data = json.loads(request.body)
        user_type = data.get('type')
        if user_type == 'user':
            user = User.objects.create(
                name=data.get('name'),
                email=data.get('email'),
                paycode=data.get('paycode')
            )
            return JsonResponse({"status": "success", "user_id": user.id})
        elif user_type == 'merchant':
            merchant = Merchant.objects.create(
                name=data.get('name'),
                email=data.get('email'),
                menu=data.get('menu')
            )
            return JsonResponse({"status": "success", "merchant_id": merchant.id})
        return JsonResponse({"status": "error", "message": "Invalid type"})

@csrf_exempt
def delete_entry(request, entry_type, entry_id):
    if request.method == "DELETE":
        if entry_type == 'user':
            user = get_object_or_404(User, id=entry_id)
            user.delete()
            return JsonResponse({"status": "success", "message": "User deleted"})
        elif entry_type == 'merchant':
            merchant = get_object_or_404(Merchant, id=entry_id)
            merchant.delete()
            return JsonResponse({"status": "success", "message": "Merchant deleted"})
        return JsonResponse({"status": "error", "message": "Invalid type"})

from django.shortcuts import render
from decimal import Decimal,InvalidOperation
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from django.db.models import Q
from django.utils.dateparse import parse_date
from .models import User, Merchant, Product, Notification, Menu,  Sales
from .serializers import UserSerializer, MerchantSerializer, ProductSerializer, NotificationSerializer
from .utils import generate_user_paycode, generate_merchant_paycode
from django.utils import timezone
from datetime import timedelta
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
import json
from django.db import transaction
from .models import Transaction
import base64
from django.core.files.base import ContentFile
from datetime import datetime
import random
from .models import ExtraMenu   
import os
from django.conf import settings

@api_view(['POST'])
def register(request):
    account_type = request.data.get('accountType')
    profile_pic = request.FILES.get('profilePicture')
    
    # Get PIN from request or use default
    pin = request.data.get('pin', '123456')

    try:
        if account_type == 'user':
            user = User.objects.create(
                nationalid=request.data.get('nationalId'),
                paycode=generate_user_paycode(),
                profilepicture=profile_pic,
                accounttype='normal',
                email=request.data.get('email'),
                username=request.data.get('username'),
                phonenumber=request.data.get('phone'),
                password=request.data.get('password'),
                dateofbirth=parse_date(request.data.get('dateOfBirth')) if request.data.get('dateOfBirth') else None,
                pin=pin  # Add PIN
            )
            return Response({"id": user.userid, "type": "user"}, status=status.HTTP_201_CREATED)

        elif account_type == 'merchant':
            merchant = Merchant.objects.create(
                nationalid=request.data.get('nationalId'),
                merchantpaycode=generate_merchant_paycode(),
                profilepicture=profile_pic,
                businesstype=request.data.get('businessType'),
                accounttype='merchant',
                email=request.data.get('email'),
                username=request.data.get('username'),
                phonenumber=request.data.get('phone'),
                password=request.data.get('password'),
                dateofcreation=parse_date(request.data.get('dateOfCreation')) if request.data.get('dateOfCreation') else None,
                pin=pin  # Add PIN
            )
            return Response({"id": merchant.merchantid, "type": "merchant"}, status=status.HTTP_201_CREATED)
        else:
            return Response({"error": "Invalid account type"}, status=status.HTTP_400_BAD_REQUEST)
    except Exception as e:
        return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)
@api_view(['GET'])
def users(request):
    users = User.objects.all()
    return Response(UserSerializer(users, many=True).data)

@api_view(['GET'])
def merchants(request):
    merchants = Merchant.objects.all()
    return Response(MerchantSerializer(merchants, many=True).data)

@api_view(['GET'])
def products(request):
    products = Product.objects.all()
    return Response(ProductSerializer(products, many=True).data)

@api_view(['POST'])
def login(request):
    data = request.data
    email = data.get("email")
    password = data.get("password")

    if not email or not password:
        return Response({"error": "Email and password required"}, status=status.HTTP_400_BAD_REQUEST)

    # Check Users
    try:
        user = User.objects.get(email=email)
        if user.password == password:
            return Response({
                "id": user.userid,
                "email": user.email,
                "username": user.username,
                "type": "user"
            })
    except User.DoesNotExist:
        pass

    # Check Merchants
    try:
        merchant = Merchant.objects.get(email=email)
        if merchant.password == password:
            return Response({
                "id": merchant.merchantid,
                "email": merchant.email,
                "username": merchant.username,
                "type": "merchant"
            })
    except Merchant.DoesNotExist:
        pass

    return Response({"error": "Invalid credentials"}, status=status.HTTP_401_UNAUTHORIZED)

@api_view(['GET'])
def test_notifications(request):
    try:
        all_notifications = Notification.objects.all()
        
        if not all_notifications.exists():
            print("⚠️ No notifications found, creating sample...")
            Notification.objects.create(
                title="Test Notification",
                content="This is a test notification from database",
                urgency="medium",
                designated_to="user",
                date="2024-01-15 10:30:00"
            )
            all_notifications = Notification.objects.all()
        
        print(f"✅ Found {all_notifications.count()} notifications in database")
        
        serializer = NotificationSerializer(all_notifications, many=True)
        
        return Response({
            "message": "Notifications test endpoint",
            "total_count": all_notifications.count(),
            "notifications": serializer.data
        })
        
    except Exception as e:
        print(f"❌ Error in test_notifications: {str(e)}")
        return Response({"error": str(e)}, status=500)

@api_view(['GET'])
def get_user_notifications(request):
    try:
        user_email = request.query_params.get('email')
        if not user_email:
            return Response({"error": "Email parameter required"}, status=400)
        
        user_type = None
        user_id = None
        
        try:
            user = User.objects.get(email=user_email)
            user_type = 'user'
            user_id = user.userid
            print(f"✅ Found user: {user.email}, type: {user_type}, ID: {user_id}")
        except User.DoesNotExist:
            try:
                merchant = Merchant.objects.get(email=user_email)
                user_type = 'merchant'
                user_id = merchant.merchantid
                print(f"✅ Found merchant: {merchant.email}, type: {user_type}, ID: {user_id}")
            except Merchant.DoesNotExist:
                print(f"❌ User not found: {user_email}")
                return Response({"error": "User not found"}, status=404)
        
        # For merchants, get only their notifications or all merchant notifications
        if user_type == 'merchant':
            # Get general merchant notifications and order notifications for this specific merchant
            notifications = Notification.objects.filter(
                Q(designated_to='merchant') | Q(designated_to='all') | 
                Q(content__contains=f"merchant_id={user_id}") |
                Q(content__contains=f"merchant {user_id}") |
                Q(content__icontains=merchant.username)
            ).order_by('-date')[:20]
        else:
            # For regular users
            notifications = Notification.objects.filter(
                Q(designated_to='user') | Q(designated_to='all')
            ).order_by('-date')[:10]
        
        print(f"✅ Found {notifications.count()} notifications for {user_type} {user_id}")
        
        serializer = NotificationSerializer(notifications, many=True)
        unread_count = notifications.count()
        
        return Response({
            "notifications": serializer.data,
            "unread_count": unread_count,
            "user_type": user_type,
            "message": f"Found {unread_count} notifications for {user_type}"
        })
        
    except Exception as e:
        print(f"❌ Error in get_user_notifications: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({"error": str(e)}, status=500)

@api_view(['GET'])
def get_all_notifications(request):
    try:
        notifications = Notification.objects.all().order_by('-date')
        print(f"📊 Total notifications in database: {notifications.count()}")
        
        user_notifs = notifications.filter(designated_to='user')
        merchant_notifs = notifications.filter(designated_to='merchant')
        all_notifs = notifications.filter(designated_to='all')
        
        print(f"   For users: {user_notifs.count()}")
        print(f"   For merchants: {merchant_notifs.count()}")
        print(f"   For all: {all_notifs.count()}")
        
        serializer = NotificationSerializer(notifications, many=True)
        
        return Response({
            "total_count": notifications.count(),
            "user_count": user_notifs.count(),
            "merchant_count": merchant_notifs.count(),
            "all_count": all_notifs.count(),
            "notifications": serializer.data
        })
        
    except Exception as e:
        print(f"❌ Error in get_all_notifications: {str(e)}")
        return Response({"error": str(e)}, status=500)

@api_view(['GET'])
def get_user_details(request):
    try:
        user_email = request.query_params.get('email')
        if not user_email:
            return Response({"error": "Email parameter required"}, status=400)
        
        print(f"🔍 Looking for user with email: {user_email}")
        
        # Check Users
        try:
            user = User.objects.get(email=user_email)
            print(f"✅ Found USER: {user.username}, Paycode: {user.paycode}")
            
            response_data = {
                "userid": user.userid,
                "email": user.email,
                "username": user.username,
                "phone": user.phonenumber,
                "national_id": user.nationalid,
                "paycode": user.paycode,
                "profile_picture": user.profilepicture.url if user.profilepicture else None,
                "account_type": user.accounttype,
                "type": "user",
                "balance": user.balance,
                "pin": user.pin,  # Add PIN to response
            }
            
            print(f"📤 Sending user data: {response_data}")
            return Response(response_data)
            
        except User.DoesNotExist:
            print(f"❌ User not found, checking merchants...")
            pass

        # Check Merchants
        try:
            merchant = Merchant.objects.get(email=user_email)
            print(f"✅ Found MERCHANT: {merchant.username}, Paycode: {merchant.merchantpaycode}")
            
            response_data = {
                "merchantid": merchant.merchantid,
                "email": merchant.email,
                "username": merchant.username,
                "phone": merchant.phonenumber,
                "national_id": merchant.nationalid,
                "paycode": merchant.merchantpaycode,
                "merchantpaycode": merchant.merchantpaycode,
                "business_type": merchant.businesstype,
                "profile_picture": merchant.profilepicture.url if merchant.profilepicture else None,
                "account_type": merchant.accounttype,
                "type": "merchant",
                "balance": merchant.balance,
                "pin": merchant.pin,  # Add PIN to response
            }
            
            print(f"📤 Sending merchant data: {response_data}")
            return Response(response_data)
            
        except Merchant.DoesNotExist:
            print(f"❌ Merchant not found either")
            pass

        print(f"🚫 No user or merchant found with email: {user_email}")
        return Response({"error": "User not found"}, status=404)
        
    except Exception as e:
        print(f"🔥 Error in get_user_details: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({"error": str(e)}, status=500)

@api_view(['PUT'])
def update_profile(request):
    try:
        data = request.data
        email = data.get('email')
        
        if not email:
            return Response({"error": "Email is required"}, status=400)
        
        # Check Users
        try:
            user = User.objects.get(email=email)
            
            current_password = data.get('current_password')
            new_password = data.get('new_password')
            
            if current_password and new_password:
                if user.password != current_password:
                    return Response({"error": "Current password is incorrect"}, status=400)
                user.password = new_password
            
            if data.get('username'):
                if User.objects.filter(username=data['username']).exclude(email=email).exists():
                    return Response({"error": "Username already taken"}, status=400)
                user.username = data['username']
            
            if data.get('phone'):
                if User.objects.filter(phonenumber=data['phone']).exclude(email=email).exists():
                    return Response({"error": "Phone number already taken"}, status=400)
                user.phonenumber = data['phone']
            
            if data.get('national_id'):
                if User.objects.filter(nationalid=data['national_id']).exclude(email=email).exists():
                    return Response({"error": "National ID already taken"}, status=400)
                user.nationalid = data['national_id']
            
            user.save()
            
            return Response({
                "message": "Profile updated successfully",
                "username": user.username,
                "email": user.email,
                "phone": user.phonenumber
            })
            
        except User.DoesNotExist:
            pass

        # Check Merchants
        try:
            merchant = Merchant.objects.get(email=email)
            
            current_password = data.get('current_password')
            new_password = data.get('new_password')
            
            if current_password and new_password:
                if merchant.password != current_password:
                    return Response({"error": "Current password is incorrect"}, status=400)
                merchant.password = new_password
            
            if data.get('username'):
                if Merchant.objects.filter(username=data['username']).exclude(email=email).exists():
                    return Response({"error": "Username already taken"}, status=400)
                merchant.username = data['username']
            
            if data.get('phone'):
                if Merchant.objects.filter(phonenumber=data['phone']).exclude(email=email).exists():
                    return Response({"error": "Phone number already taken"}, status=400)
                merchant.phonenumber = data['phone']
            
            if data.get('national_id'):
                if Merchant.objects.filter(nationalid=data['national_id']).exclude(email=email).exists():
                    return Response({"error": "National ID already taken"}, status=400)
                merchant.nationalid = data['national_id']
            
            merchant.save()
            
            return Response({
                "message": "Profile updated successfully",
                "username": merchant.username,
                "email": merchant.email,
                "phone": merchant.phonenumber
            })
            
        except Merchant.DoesNotExist:
            pass

        return Response({"error": "User not found"}, status=404)
        
    except Exception as e:
        return Response({"error": str(e)}, status=500)

@api_view(['PUT'])
def update_profile_picture(request):
    try:
        email = request.data.get('email')
        profile_pic = request.FILES.get('profilePicture')
        
        if not email:
            return Response({"error": "Email is required"}, status=400)
        
        if not profile_pic:
            return Response({"error": "Profile picture is required"}, status=400)
        
        # Check Users
        try:
            user = User.objects.get(email=email)
            
            if user.profilepicture:
                user.profilepicture.delete(save=False)
            
            user.profilepicture = profile_pic
            user.save()
            
            return Response({
                "message": "Profile picture updated successfully",
                "profile_picture": user.profilepicture.url
            })
            
        except User.DoesNotExist:
            pass

        # Check Merchants
        try:
            merchant = Merchant.objects.get(email=email)
            
            if merchant.profilepicture:
                merchant.profilepicture.delete(save=False)
            
            merchant.profilepicture = profile_pic
            merchant.save()
            
            return Response({
                "message": "Profile picture updated successfully",
                "profile_picture": merchant.profilepicture.url
            })
            
        except Merchant.DoesNotExist:
            pass

        return Response({"error": "User not found"}, status=404)
        
    except Exception as e:
        return Response({"error": str(e)}, status=500)

@csrf_exempt
def find_user_by_paycode(request):
    if request.method == 'GET':
        paycode = request.GET.get('paycode', '').strip()
        
        if not paycode:
            return JsonResponse({
                'error': 'Paycode is required',
                'username': None
            }, status=400)
        
        try:
            print(f"🔍 Searching for paycode: {paycode}")
            
            # Search in User model
            try:
                user = User.objects.get(paycode=paycode)
                print(f"✅ Found USER: {user.username}")
                return JsonResponse({
                    'success': True,
                    'username': user.username,
                    'email': user.email,
                    'phone': user.phonenumber,
                    'type': 'user',
                    'paycode': user.paycode,
                    'profile_picture': user.profilepicture.url if user.profilepicture else None,
                    'error': None
                })
            except User.DoesNotExist:
                print(f"ℹ️ Not found in User, checking Merchant...")
                pass
            
            # Search in Merchant model
            try:
                merchant = Merchant.objects.get(merchantpaycode=paycode)
                print(f"✅ Found MERCHANT: {merchant.username}")
                return JsonResponse({
                    'success': True,
                    'username': merchant.username,
                    'email': merchant.email,
                    'phone': merchant.phonenumber,
                    'type': 'merchant',
                    'paycode': merchant.merchantpaycode,
                    'business_type': merchant.businesstype,
                    'profile_picture': merchant.profilepicture.url if merchant.profilepicture else None,
                    'error': None
                })
            except Merchant.DoesNotExist:
                print(f"❌ Not found in Merchant either")
                pass
            
            return JsonResponse({
                'success': False,
                'error': 'User not found',
                'username': None
            }, status=404)
                
        except Exception as e:
            print(f"🔥 Error in find_user_by_paycode: {str(e)}")
            import traceback
            traceback.print_exc()
            return JsonResponse({
                'success': False,
                'error': str(e)
            }, status=500)
    
    return JsonResponse({
        'success': False,
        'error': 'Invalid request method'
    }, status=400)

# =============================================
# MERCHANT PRODUCT MANAGEMENT ENDPOINTS
# =============================================

@api_view(['GET'])
def merchant_details(request):
    """
    Get merchant details by email OR merchant ID
    """
    try:
        email = request.GET.get('email')
        merchant_id = request.GET.get('merchant_id')
        
        if not email and not merchant_id:
            return Response({"error": "Email or Merchant ID parameter required"}, status=400)
        
        merchant = None
        
        if email:
            print(f"🔍 Looking for merchant with email: {email}")
            try:
                merchant = Merchant.objects.get(email=email)
            except Merchant.DoesNotExist:
                return Response({"error": "Merchant not found with this email"}, status=404)
        
        elif merchant_id:
            print(f"🔍 Looking for merchant with ID: {merchant_id}")
            try:
                merchant_id = int(merchant_id)
                merchant = Merchant.objects.get(merchantid=merchant_id)
            except ValueError:
                return Response({"error": "Invalid merchant ID"}, status=400)
            except Merchant.DoesNotExist:
                return Response({"error": "Merchant not found with this ID"}, status=404)
        
        if merchant:
            print(f"✅ Found MERCHANT: {merchant.username}, ID: {merchant.merchantid}")
            
            response_data = {
                "merchantid": merchant.merchantid,
                "email": merchant.email,
                "username": merchant.username,
                "phone": merchant.phonenumber,
                "national_id": merchant.nationalid,
                "merchantpaycode": merchant.merchantpaycode,
                "business_type": merchant.businesstype,
                "profile_picture": merchant.profilepicture.url if merchant.profilepicture else None,
                "account_type": merchant.accounttype,
                "type": "merchant",
                "balance": merchant.balance,
                "dateofcreation": merchant.dateofcreation,
                "pin": merchant.pin,
            }
            
            return Response(response_data)
        else:
            return Response({"error": "Merchant not found"}, status=404)
            
    except Exception as e:
        print(f"🔥 Error in merchant_details: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({"error": str(e)}, status=500)
@api_view(['GET'])
def get_merchant_payment_details(request):
    """
    Get merchant payment details for processing payments
    """
    try:
        merchant_id = request.GET.get('merchant_id')
        
        if not merchant_id:
            return Response({"error": "Merchant ID parameter required"}, status=400)
        
        try:
            merchant_id = int(merchant_id)
            merchant = Merchant.objects.get(merchantid=merchant_id)
            
            response_data = {
                "success": True,
                "merchant_id": merchant.merchantid,
                "merchant_name": merchant.username,
                "merchant_email": merchant.email,
                "merchant_paycode": merchant.merchantpaycode,
                "message": "Merchant payment details retrieved successfully"
            }
            
            return Response(response_data)
            
        except ValueError:
            return Response({"error": "Invalid merchant ID"}, status=400)
        except Merchant.DoesNotExist:
            return Response({"error": "Merchant not found"}, status=404)
            
    except Exception as e:
        print(f"🔥 Error in get_merchant_payment_details: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({"error": str(e)}, status=500)

@api_view(['POST'])
def create_product(request):
    """
    Create a new product and optionally add it to menu
    """
    try:
        data = request.data
        
        # Get merchant ID
        merchant_id = data.get('merchant_id')
        if not merchant_id:
            return Response({"error": "Merchant ID is required"}, status=400)
        
        # Validate merchant exists
        try:
            merchant = Merchant.objects.get(merchantid=merchant_id)
        except Merchant.DoesNotExist:
            return Response({"error": "Merchant not found"}, status=404)
        
        # Generate product ID (timestamp + random)
        product_id = int(datetime.now().timestamp() * 1000) + random.randint(1000, 9999)
        
        # Handle image upload
        product_picture_url = None
        if 'product_picture' in request.FILES:
            image_file = request.FILES['product_picture']
            
            # Generate unique filename
            import uuid
            ext = os.path.splitext(image_file.name)[1]  # Get file extension
            filename = f"product_{product_id}_{uuid.uuid4().hex[:8]}{ext}"
            
            # Define upload path
            upload_path = os.path.join('product_images', filename)
            full_path = os.path.join(settings.MEDIA_ROOT, upload_path)
            
            # Create directory if it doesn't exist
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            
            # Save the file
            with open(full_path, 'wb+') as destination:
                for chunk in image_file.chunks():
                    destination.write(chunk)
            
            # Set the URL for the saved file
            product_picture_url = os.path.join(settings.MEDIA_URL, upload_path)
            print(f"✅ Image saved: {product_picture_url}")
        else:
            print("⚠️ No image uploaded")
        
        # Create product with IntegerField for merchantid
        product = Product.objects.create(
            productid=product_id,
            productname=data.get('product_name'),
            price=Decimal(str(data.get('price', 0.0))),
            amountinstock=int(data.get('amount_in_stock', 0)),
            category=data.get('category', ''),
            merchantid=merchant_id,
            productpicture=product_picture_url if product_picture_url else '',  # Store URL string, not file object
        )
        
        # Automatically add to menu (default behavior)
        add_to_menu_flag = data.get('add_to_menu', 'true').lower() == 'true'
        if add_to_menu_flag:
            menu_item = Menu.objects.create(
                merchantid=merchant_id,
                productid=product_id,
                availability=(product.amountinstock > 0)
            )
            print(f"✅ Added to menu: Menu ID {menu_item.menuid}")
        
        # Handle custom fields (EtraMenu)
        custom_fields = data.get('custom_fields', [])
        if isinstance(custom_fields, str):
            try:
                custom_fields = json.loads(custom_fields)
            except json.JSONDecodeError:
                custom_fields = []
        
        for field_name in custom_fields:
            if field_name and field_name.strip():
                ExtraMenu.objects.create(
                    merchantid=merchant_id,
                    fieldname=field_name.strip()
                )
        
        # Build the full URL for the response
        product_data = {
            'productid': product.productid,
            'productname': product.productname,
            'price': float(product.price),
            'amountinstock': product.amountinstock,
            'category': product.category,
            'merchantid': product.merchantid,
            'productpicture': product.productpicture,
        }
        
        return Response({
            'success': True,
            'product_id': product_id,
            'product_name': product.productname,
            'message': 'Product created successfully',
            'menu_added': add_to_menu_flag,
            'product': product_data
        }, status=201)
        
    except Exception as e:
        print(f"🔥 Error in create_product: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e), 'debug': 'Check server logs for details'}, status=400)

@api_view(['GET'])
def merchant_products(request):
    """
    Get all products for a specific merchant
    """
    merchant_id = request.GET.get('merchant_id')
    
    if not merchant_id:
        return Response({"error": "Merchant ID parameter required"}, status=400)
    
    try:
        # Convert to integer
        merchant_id = int(merchant_id)
        
        # Get products for this merchant
        products = Product.objects.filter(merchantid=merchant_id)
        
        # Format response data
        products_data = []
        for product in products:
            # Handle product picture URL
            product_picture_url = None
            if product.productpicture:
                # If it's a relative path, make it absolute
                if isinstance(product.productpicture, str):
                    if product.productpicture.startswith('/'):
                        product_picture_url = product.productpicture
                    else:
                        product_picture_url = f"/media/{product.productpicture}"
                else:
                    # It's an ImageField
                    product_picture_url = product.productpicture.url if product.productpicture else None
            
            products_data.append({
                'productid': product.productid,
                'productname': product.productname,
                'price': float(product.price),
                'amountinstock': product.amountinstock,
                'category': product.category,
                'merchantid': product.merchantid,
                'productpicture': product_picture_url,
            })
        
        return Response({
            'success': True,
            'count': len(products_data),
            'products': products_data
        })
        
    except ValueError:
        return Response({"error": "Invalid merchant ID"}, status=400)
    except Exception as e:
        print(f"🔥 Error in merchant_products: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=400)
    
@api_view(['GET'])
def merchant_menu(request):
    """
    Get menu items for a specific merchant
    """
    merchant_id = request.GET.get('merchant_id')
    
    if not merchant_id:
        return Response({"error": "Merchant ID parameter required"}, status=400)
    
    try:
        # Convert to integer
        merchant_id = int(merchant_id)
        
        # Get menu items for this merchant
        menu_items = Menu.objects.filter(merchantid=merchant_id)
        
        # Format response with product details
        menu_data = []
        for menu_item in menu_items:
            try:
                # Get the product
                product = Product.objects.get(productid=menu_item.productid)
                
                # Handle product picture URL
                product_picture_url = None
                if product.productpicture:
                    if isinstance(product.productpicture, str):
                        if product.productpicture.startswith('/'):
                            product_picture_url = product.productpicture
                        else:
                            product_picture_url = f"/media/{product.productpicture}"
                    else:
                        product_picture_url = product.productpicture.url if product.productpicture else None
                
                menu_data.append({
                    'menuid': menu_item.menuid,
                    'productid': product.productid,
                    'productname': product.productname,
                    'price': float(product.price),
                    'amountinstock': product.amountinstock,
                    'category': product.category,
                    'productpicture': product_picture_url,
                    'availability': menu_item.availability
                })
            except Product.DoesNotExist:
                print(f"⚠️ Product {menu_item.productid} not found for menu item {menu_item.menuid}")
                continue
        
        return Response({
            'success': True,
            'count': len(menu_data),
            'menu': menu_data
        })
        
    except ValueError:
        return Response({"error": "Invalid merchant ID"}, status=400)
    except Exception as e:
        print(f"🔥 Error in merchant_menu: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=400)

@api_view(['POST'])
def add_to_menu(request):
    """
    Add an existing product to merchant's menu
    """
    try:
        data = request.data
        
        merchant_id = data.get('merchant_id')
        product_id = data.get('product_id')
        
        if not merchant_id or not product_id:
            return Response({"error": "Merchant ID and Product ID are required"}, status=400)
        
        try:
            merchant = Merchant.objects.get(merchantid=merchant_id)
            product = Product.objects.get(productid=product_id, merchantid=merchant_id)  # Changed to merchant_id
        except (Merchant.DoesNotExist, Product.DoesNotExist) as e:
            return Response({"error": "Merchant or Product not found"}, status=404)
        
        # Check if already in menu
        existing_menu = Menu.objects.filter(merchantid=merchant_id, productid=product_id).first()
        if existing_menu:
            return Response({
                'success': True,
                'message': 'Product is already in menu',
                'menuid': existing_menu.menuid
            })
        
        # Add to menu - PASS INTEGER VALUES, NOT OBJECTS
        menu_item = Menu.objects.create(
            merchantid=merchant_id,  # Pass integer ID
            productid=product_id,    # Pass integer ID
            availability=data.get('availability', True)
        )
        
        return Response({
            'success': True,
            'menuid': menu_item.menuid,
            'product_name': product.productname,
            'message': 'Product added to menu successfully'
        }, status=201)
        
    except Exception as e:
        print(f"🔥 Error in add_to_menu: {str(e)}")
        return Response({'error': str(e)}, status=400)

@api_view(['DELETE'])
def remove_from_menu(request):
    """
    Remove a product from merchant's menu
    """
    menu_id = request.GET.get('menu_id')
    
    if not menu_id:
        return Response({"error": "Menu ID parameter required"}, status=400)
    
    try:
        menu_item = Menu.objects.get(menuid=menu_id)
        
        # Get product name before deletion
        product_name = "Unknown"
        try:
            product = Product.objects.get(productid=menu_item.productid)  # menu_item.productid is already an integer
            product_name = product.productname
        except Product.DoesNotExist:
            pass
            
        menu_item.delete()
        
        return Response({
            'success': True, 
            'message': f'Product "{product_name}" removed from menu'
        })
        
    except Menu.DoesNotExist:
        return Response({"error": "Menu item not found"}, status=404)
    except Exception as e:
        print(f"🔥 Error in remove_from_menu: {str(e)}")
        return Response({'error': str(e)}, status=400)

@api_view(['GET'])
def merchant_custom_fields(request):
    """
    Get custom fields for a specific merchant
    """
    merchant_id = request.GET.get('merchant_id')
    
    if not merchant_id:
        return Response({"error": "Merchant ID parameter required"}, status=400)
    
    try:
        merchant = Merchant.objects.get(merchantid=merchant_id)
        custom_fields = ExtraMenu.objects.filter(merchantid=merchant)
        
        field_names = [field.fieldname for field in custom_fields]
        
        return Response({
            'success': True,
            'custom_fields': field_names,
            'count': len(field_names)
        })
        
    except Merchant.DoesNotExist:
        return Response({"error": "Merchant not found"}, status=404)
    except Exception as e:
        print(f"🔥 Error in merchant_custom_fields: {str(e)}")
        return Response({'error': str(e)}, status=400)

@api_view(['PUT'])
def update_product(request):
    """
    Update product information
    """
    try:
        data = request.data
        product_id = data.get('product_id')
        
        if not product_id:
            return Response({"error": "Product ID is required"}, status=400)
        
        try:
            product = Product.objects.get(productid=product_id)
        except Product.DoesNotExist:
            return Response({"error": "Product not found"}, status=404)
        
        # Update fields
        if 'product_name' in data:
            product.productname = data['product_name']
        if 'price' in data:
            product.price = data['price']
        if 'amount_in_stock' in data:
            product.amountinstock = data['amount_in_stock']
        if 'category' in data:
            product.category = data['category']
        
        # Handle image update
        if 'product_picture' in request.FILES:
            # Delete old image if exists
            if product.productpicture:
                product.productpicture.delete(save=False)
            product.productpicture = request.FILES['product_picture']
        
        product.save()
        
        # Update menu availability if needed
        if 'availability' in data:
            menu_items = Menu.objects.filter(productid=product)
            for menu_item in menu_items:
                menu_item.availability = data['availability']
                menu_item.save()
        
        serializer = ProductSerializer(product)
        
        return Response({
            'success': True,
            'message': 'Product updated successfully',
            'product': serializer.data
        })
        
    except Exception as e:
        print(f"🔥 Error in update_product: {str(e)}")
        return Response({'error': str(e)}, status=400)

@api_view(['DELETE'])
def delete_product(request):
    """
    Delete a product and remove it from menu
    """
    product_id = request.GET.get('product_id')
    
    if not product_id:
        return Response({"error": "Product ID parameter required"}, status=400)
    
    try:
        product = Product.objects.get(productid=product_id)
        product_name = product.productname
        
        # Delete from menu first - FIXED: Use product_id integer
        Menu.objects.filter(productid=product_id).delete()  # Changed to product_id
        
        # Delete product
        product.delete()
        
        return Response({
            'success': True, 
            'message': f'Product "{product_name}" deleted successfully'
        })
        
    except Product.DoesNotExist:
        return Response({"error": "Product not found"}, status=404)
    except Exception as e:
        print(f"🔥 Error in delete_product: {str(e)}")
        return Response({'error': str(e)}, status=400)

@api_view(['PUT'])
def toggle_product_availability(request):
    """
    Toggle product availability (stock) and update menu
    """
    try:
        data = request.data
        product_id = data.get('product_id')
        
        if not product_id:
            return Response({"error": "Product ID is required"}, status=400)
        
        try:
            product = Product.objects.get(productid=product_id)
            
            # Toggle stock (0 = not available, >0 = available)
            if product.amountinstock > 0:
                product.amountinstock = 0
                status_msg = "unavailable"
            else:
                product.amountinstock = 10  # Default stock when making available
                status_msg = "available"
            
            product.save()
            
            # Update menu availability - FIXED: Use productid INTEGER, not Product object
            menu_items = Menu.objects.filter(productid=product_id)  # Changed to product_id (integer)
            for menu_item in menu_items:
                menu_item.availability = (product.amountinstock > 0)
                menu_item.save()
            
            return Response({
                'success': True,
                'available': product.amountinstock > 0,
                'stock': product.amountinstock,
                'message': f'Product is now {status_msg}'
            })
            
        except Product.DoesNotExist:
            return Response({"error": "Product not found"}, status=404)
        
    except Exception as e:
        print(f"🔥 Error in toggle_product_availability: {str(e)}")
        return Response({'error': str(e)}, status=400)

@api_view(['POST'])
def upload_product_image(request):
    """
    Upload product image (standalone endpoint)
    """
    try:
        if 'image' not in request.FILES:
            return Response({'error': 'No image uploaded'}, status=400)
        
        image_file = request.FILES['image']
        merchant_email = request.POST.get('merchant_email')
        product_name = request.POST.get('product_name', 'product')
        
        # Generate filename
        timestamp = int(datetime.now().timestamp())
        filename = f"product_{merchant_email}_{product_name}_{timestamp}.jpg"
        
        # Save the file
        from django.core.files.storage import default_storage
        saved_path = default_storage.save(f'product_images/{filename}', ContentFile(image_file.read()))
        
        # Return URL
        image_url = f"/media/product_images/{filename}"
        
        return Response({
            'success': True,
            'image_url': image_url,
            'message': 'Image uploaded successfully'
        })
        
    except Exception as e:
        print(f"🔥 Error in upload_product_image: {str(e)}")
        return Response({'error': str(e)}, status=400)

@api_view(['GET'])
def get_categories(request):
    """
    Get all available product categories
    """
    try:
        # Get unique categories from products
        categories = Product.objects.values_list('category', flat=True).distinct()
        
        # Add default categories if none exist
        if not categories:
            categories = [
                "Fresh sea products",
                "Bakery",
                "Beverages",
                "Snacks",
                "Meals",
                "Desserts",
                "Groceries",
                "Electronics",
                "Clothing"
            ]
        
        return Response({
            'success': True,
            'categories': list(categories)
        })
        
    except Exception as e:
        print(f"🔥 Error in get_categories: {str(e)}")
        return Response({'error': str(e)}, status=400)
@api_view(['POST'])
def process_payment(request):
    """
    Process a payment between two users/merchants
    """
    try:
        data = request.data
        
        # Get payment details
        sender_paycode = data.get('sender_paycode')
        receiver_paycode = data.get('receiver_paycode')
        pin = data.get('pin')
        amount = data.get('amount')
        
        if not all([sender_paycode, receiver_paycode, pin, amount]):
            return Response({"success": False, "error": "All fields are required"}, status=400)
        
        try:
            # Convert amount to Decimal immediately
            amount_decimal = Decimal(str(amount))
            if amount_decimal <= Decimal('0'):
                return Response({"success": False, "error": "Amount must be positive"}, status=400)
        except (ValueError, InvalidOperation):
            return Response({"success": False, "error": "Invalid amount"}, status=400)
        
        # Find sender (can be user or merchant)
        sender = None
        sender_type = None
        
        # Check if sender is a user
        try:
            user_sender = User.objects.get(paycode=sender_paycode)
            sender = user_sender
            sender_type = 'user'
            print(f"✅ Sender is USER: {user_sender.username}")
        except User.DoesNotExist:
            pass
        
        # Check if sender is a merchant
        if not sender:
            try:
                merchant_sender = Merchant.objects.get(merchantpaycode=sender_paycode)
                sender = merchant_sender
                sender_type = 'merchant'
                print(f"✅ Sender is MERCHANT: {merchant_sender.username}")
            except Merchant.DoesNotExist:
                return Response({"success": False, "error": "Sender not found"}, status=404)
        
        # Verify PIN
        if str(sender.pin) != str(pin):
            return Response({"success": False, "error": "Invalid PIN"}, status=400)
        
        # Check sender balance
        sender_balance = sender.balance if hasattr(sender, 'balance') else Decimal('0')
        
        # Calculate charge (20 RWF) as Decimal
        charge = Decimal('20.0')
        total_amount = amount_decimal + charge
        
        # Check if sender has sufficient balance
        if sender_balance < total_amount:
            return Response({
                "success": False, 
                "error": f"Insufficient balance. Available: {sender_balance} RWF, Required: {total_amount} RWF"
            }, status=400)
        
        # Find receiver (can be user or merchant)
        receiver = None
        receiver_type = None
        
        # Check if receiver is a user
        try:
            user_receiver = User.objects.get(paycode=receiver_paycode)
            receiver = user_receiver
            receiver_type = 'user'
            print(f"✅ Receiver is USER: {user_receiver.username}")
        except User.DoesNotExist:
            pass
        
        # Check if receiver is a merchant
        if not receiver:
            try:
                merchant_receiver = Merchant.objects.get(merchantpaycode=receiver_paycode)
                receiver = merchant_receiver
                receiver_type = 'merchant'
                print(f"✅ Receiver is MERCHANT: {merchant_receiver.username}")
            except Merchant.DoesNotExist:
                return Response({"success": False, "error": "Receiver not found"}, status=404)
        
        # Check if sender is trying to pay themselves
        if sender_paycode == receiver_paycode:
            return Response({"success": False, "error": "Cannot send money to yourself"}, status=400)
        
        # Start transaction
        with transaction.atomic():
            # Deduct from sender (both are Decimal now)
            sender.balance -= total_amount
            sender.save()
            
            # Add to receiver (only the amount, not the charge)
            receiver.balance += amount_decimal
            receiver.save()
            
            # Create transaction record
            transaction_id = int(datetime.now().timestamp() * 1000)
            
            # Determine sender and receiver IDs based on type
            sender_id = sender.userid if sender_type == 'user' else sender.merchantid
            receiver_id = receiver.userid if receiver_type == 'user' else receiver.merchantid
            
            # Create transaction record with sender and receiver types
            trans = Transaction.objects.create(
                transactionid=transaction_id,
                transfertype='Normal transfer',
                senderid=sender_id,
                receiverid=receiver_id,
                amount=amount_decimal,
                charge=charge,
                status='success',
                sender_type=sender_type,
                receiver_type=receiver_type
            )
            
            print(f"💾 Stored transaction: Sender ({sender_type}) ID: {sender_id} -> Receiver ({receiver_type}) ID: {receiver_id}")
            
            # Return success response
            return Response({
                "success": True,
                "message": "Payment successful",
                "transaction_id": transaction_id,
                "amount": float(amount_decimal),
                "charge": float(charge),
                "total_deducted": float(total_amount),
                "sender_balance": float(sender.balance),
                "receiver_balance": float(receiver.balance),
                "receiver_name": receiver.username,
                "receiver_type": receiver_type,
                "sender_type": sender_type,
            }, status=200)
            
    except Exception as e:
        print(f"🔥 Error in process_payment: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({"success": False, "error": str(e)}, status=500)
@api_view(['GET'])
def get_user_transactions(request):
    """
    Get all transactions for a specific user/merchant with filtering
    """
    try:
        email = request.GET.get('email')
        year = request.GET.get('year')
        month = request.GET.get('month')
        day = request.GET.get('day')
        
        if not email:
            return Response({"error": "Email parameter required"}, status=400)
        
        # Find user
        user = None
        user_id = None
        user_type = None
        
        # Check Users
        try:
            user = User.objects.get(email=email)
            user_id = user.userid
            user_type = 'user'
            user_balance = user.balance if hasattr(user, 'balance') else 5000.00
            print(f"✅ Found USER: {user.username}, ID: {user_id}, Balance: {user_balance}")
        except User.DoesNotExist:
            pass
        
        # Check Merchants
        if not user:
            try:
                merchant = Merchant.objects.get(email=email)
                user = merchant
                user_id = merchant.merchantid
                user_type = 'merchant'
                user_balance = merchant.balance if hasattr(merchant, 'balance') else 5000.00
                print(f"✅ Found MERCHANT: {merchant.username}, ID: {user_id}, Balance: {user_balance}")
            except Merchant.DoesNotExist:
                return Response({"error": "User not found"}, status=404)
        
        # Get all transactions where user is either sender or receiver
        # Since we need to handle both user and merchant IDs, we'll query without filtering by type first
        transactions = Transaction.objects.filter(
            Q(senderid=user_id) | Q(receiverid=user_id)
        ).order_by('-date')
        
        # Apply filters
        if year:
            transactions = transactions.filter(date__year=int(year))
            print(f"📅 Filtering by year: {year}")
        
        if month:
            transactions = transactions.filter(date__month=int(month))
            print(f"📅 Filtering by month: {month}")
        
        if day:
            transactions = transactions.filter(date__day=int(day))
            print(f"📅 Filtering by day: {day}")
        
        print(f"📊 Found {transactions.count()} transactions")
        
        # Format response
        transaction_data = []
        for trans in transactions:
            # Determine transaction type
            is_sender = trans.senderid == user_id
            is_receiver = trans.receiverid == user_id
            
            # Get other party details using the sender_type and receiver_type fields
            other_party_id = trans.receiverid if is_sender else trans.senderid
            other_party_type = trans.receiver_type if is_sender else trans.sender_type
            other_party_name = "Unknown"
            
            # Try to get other party name based on their type
            try:
                if other_party_type == 'user':
                    # Other party is a user
                    other_user = User.objects.get(userid=other_party_id)
                    other_party_name = other_user.username
                elif other_party_type == 'merchant':
                    # Other party is a merchant
                    other_merchant = Merchant.objects.get(merchantid=other_party_id)
                    other_party_name = other_merchant.username
                else:
                    # Type not specified, try both
                    try:
                        other_user = User.objects.get(userid=other_party_id)
                        other_party_name = other_user.username
                        other_party_type = 'user'
                    except User.DoesNotExist:
                        try:
                            other_merchant = Merchant.objects.get(merchantid=other_party_id)
                            other_party_name = other_merchant.username
                            other_party_type = 'merchant'
                        except Merchant.DoesNotExist:
                            other_party_name = f"Account {other_party_id}"
            except Exception as e:
                print(f"⚠️ Could not find other party (ID: {other_party_id}, Type: {other_party_type}): {e}")
                other_party_name = f"Account {other_party_id}"
            
            # Calculate total for sent transactions
            if is_sender:
                total_amount = trans.amount + trans.charge if trans.amount and trans.charge else trans.amount
            else:
                total_amount = trans.amount
            
            transaction_data.append({
                'transaction_id': trans.transactionid,
                'date': trans.date.strftime('%d %B %Y %H:%M') if trans.date else 'Unknown date',
                'short_date': trans.date.strftime('%d %b %Y') if trans.date else 'Unknown date',
                'amount': float(trans.amount) if trans.amount else 0.0,
                'charge': float(trans.charge) if trans.charge else 0.0,
                'type': 'sent' if is_sender else 'received',
                'other_party': other_party_name,
                'other_party_type': other_party_type,
                'status': trans.status if trans.status else 'success',
                'total': float(total_amount) if total_amount else 0.0
            })
        
        return Response({
            'success': True,
            'user_type': user_type,
            'username': user.username,
            'balance': float(user_balance),
            'user_id': user_id,
            'total_transactions': len(transaction_data),
            'transactions': transaction_data
        })
        
    except Exception as e:
        print(f"🔥 Error in get_user_transactions: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=500)
@api_view(['GET'])
def test_endpoint(request):
    """Simple test endpoint to check if API is working"""
    return Response({
        'status': 'ok',
        'message': 'Django API is running',
        'time': datetime.now().isoformat()
    })

import random
from datetime import datetime
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from django.db import transaction
from .models import Order
from .serializers import OrderSerializer

@api_view(['POST'])
def create_order(request):
    """
    Create a new order
    """
    try:
        data = request.data
        
        # Validate required fields
        required_fields = ['order_number', 'customer_id', 'customer_type', 'customer_name',
                          'merchant_id', 'merchant_name', 'items', 'total_amount']
        
        for field in required_fields:
            if field not in data:
                return Response({
                    'success': False,
                    'error': f'Missing required field: {field}'
                }, status=status.HTTP_400_BAD_REQUEST)
        
        # Generate unique order ID (timestamp + random)
        order_id = int(datetime.now().timestamp() * 1000) + random.randint(1000, 9999)
        
        # Create order
        with transaction.atomic():
            order = Order.objects.create(
                orderid=order_id,
                order_number=data['order_number'],
                customer_id=data['customer_id'],
                customer_type=data['customer_type'],
                customer_name=data['customer_name'],
                merchant_id=data['merchant_id'],
                merchant_name=data['merchant_name'],
                table_name=data.get('table_name', ''),
                items=data['items'],
                custom_fields=data.get('custom_fields', {}),
                total_amount=data['total_amount'],
                status=data.get('status', 'pending')
            )
            
            # Update product stock if needed
            _update_product_stock(data['items'], data['merchant_id'])
            
            # Create notification for merchant
            _create_order_notification(order)
        
        serializer = OrderSerializer(order)
        
        return Response({
            'success': True,
            'message': 'Order created successfully',
            'order_id': order_id,
            'order': serializer.data
        }, status=status.HTTP_201_CREATED)
        
    except Exception as e:
        print(f"🔥 Error creating order: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({
            'success': False,
            'error': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

def _update_product_stock(items, merchant_id):
    """
    Update product stock after order
    """
    try:
        from .models import Product
        
        for item in items:
            product_id = item.get('productid')
            quantity = item.get('quantity', 0)
            
            if product_id and quantity > 0:
                try:
                    product = Product.objects.get(
                        productid=product_id,
                        merchantid=merchant_id
                    )
                    
                    # Reduce stock
                    new_stock = max(0, product.amountinstock - quantity)
                    product.amountinstock = new_stock
                    product.save()
                    
                    # Update menu availability
                    from .models import Menu
                    menu_items = Menu.objects.filter(
                        merchantid=merchant_id,
                        productid=product_id
                    )
                    for menu_item in menu_items:
                        menu_item.availability = (new_stock > 0)
                        menu_item.save()
                        
                except Product.DoesNotExist:
                    print(f"⚠️ Product {product_id} not found")
                    continue
                    
    except Exception as e:
        print(f"⚠️ Error updating stock: {e}")

def _create_order_notification(order):
    """
    Create notification for merchant about new order
    """
    try:
        from .models import Notification
        
        Notification.objects.create(
            title=f"New Order #{order.order_number}",
            content=f"New order from {order.customer_name}. Total: {order.total_amount} RWF",
            urgency="high",
            designated_to="merchant",
            date=datetime.now()
        )
        
    except Exception as e:
        print(f"⚠️ Error creating notification: {e}")

@api_view(['GET'])
def get_customer_orders(request):
    """
    Get all orders for a specific customer
    """
    customer_id = request.GET.get('customer_id')
    customer_type = request.GET.get('customer_type')
    
    if not customer_id or not customer_type:
        return Response({"error": "Customer ID and type required"}, status=400)
    
    try:
        orders = Order.objects.filter(
            customer_id=customer_id,
            customer_type=customer_type
        ).order_by('-created_at')
        
        serializer = OrderSerializer(orders, many=True)
        
        return Response({
            'success': True,
            'count': orders.count(),
            'orders': serializer.data
        })
        
    except Exception as e:
        return Response({'error': str(e)}, status=500)

@api_view(['GET'])
def get_merchant_orders(request):
    """
    Get all orders for a specific merchant
    """
    merchant_id = request.GET.get('merchant_id')
    
    if not merchant_id:
        return Response({"error": "Merchant ID required"}, status=400)
    
    try:
        orders = Order.objects.filter(
            merchant_id=merchant_id
        ).order_by('-created_at')
        
        serializer = OrderSerializer(orders, many=True)
        
        return Response({
            'success': True,
            'count': orders.count(),
            'orders': serializer.data
        })
        
    except Exception as e:
        return Response({'error': str(e)}, status=500)

@api_view(['PUT'])
def update_order_status(request):
    """
    Update order status
    """
    order_id = request.data.get('order_id')
    new_status = request.data.get('status')
    
    if not order_id or not new_status:
        return Response({"error": "Order ID and status required"}, status=400)
    
    valid_statuses = ['pending', 'confirmed', 'preparing', 'ready', 'delivered', 'cancelled']
    
    if new_status not in valid_statuses:
        return Response({"error": f"Invalid status. Must be one of: {valid_statuses}"}, status=400)
    
    try:
        order = Order.objects.get(orderid=order_id)
        order.status = new_status
        order.save()
        
        # Create notification for customer
        _create_status_notification(order)
        
        serializer = OrderSerializer(order)
        
        return Response({
            'success': True,
            'message': f'Order status updated to {new_status}',
            'order': serializer.data
        })
        
    except Order.DoesNotExist:
        return Response({"error": "Order not found"}, status=404)
    except Exception as e:
        return Response({'error': str(e)}, status=500)

def _create_status_notification(order):
    """
    Create notification for customer about order status change
    """
    try:
        from .models import Notification
        
        status_messages = {
            'confirmed': 'Your order has been confirmed',
            'preparing': 'Your order is being prepared',
            'ready': 'Your order is ready for pickup',
            'delivered': 'Your order has been delivered',
            'cancelled': 'Your order has been cancelled'
        }
        
        if order.status in status_messages:
            Notification.objects.create(
                title=f"Order #{order.order_number} Update",
                content=f"{status_messages[order.status]} by {order.merchant_name}",
                urgency="medium",
                designated_to=order.customer_type,
                date=datetime.now()
            )
        
    except Exception as e:
        print(f"⚠️ Error creating status notification: {e}")

@api_view(['GET'])
def get_order_details(request):
    """
    Get detailed information about a specific order
    """
    order_id = request.GET.get('order_id')
    
    if not order_id:
        return Response({"error": "Order ID required"}, status=400)
    
    try:
        order = Order.objects.get(orderid=order_id)
        serializer = OrderSerializer(order)
        
        return Response({
            'success': True,
            'order': serializer.data
        })
        
    except Order.DoesNotExist:
        return Response({"error": "Order not found"}, status=404)
    except Exception as e:
        return Response({'error': str(e)}, status=500)
@api_view(['GET'])
def get_customer_orders(request):
    """
    Get all orders for a specific customer
    """
    try:
        customer_id = request.GET.get('customer_id')
        customer_type = request.GET.get('customer_type')
        
        if not customer_id or not customer_type:
            return Response({"error": "Customer ID and type required"}, status=400)
        
        # Convert customer_id to integer
        try:
            customer_id = int(customer_id)
        except ValueError:
            return Response({"error": "Invalid customer ID"}, status=400)
        
        # Get orders for this customer
        orders = Order.objects.filter(
            customer_id=customer_id,
            customer_type=customer_type
        ).order_by('-created_at')
        
        # Serialize the orders
        serializer = OrderSerializer(orders, many=True)
        
        return Response({
            'success': True,
            'count': orders.count(),
            'orders': serializer.data
        })
        
    except Exception as e:
        print(f"🔥 Error in get_customer_orders: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=500)

@api_view(['GET'])
def get_merchant_orders(request):
    """
    Get all orders for a specific merchant
    """
    try:
        merchant_id = request.GET.get('merchant_id')
        
        if not merchant_id:
            return Response({"error": "Merchant ID required"}, status=400)
        
        # Convert merchant_id to integer
        try:
            merchant_id = int(merchant_id)
        except ValueError:
            return Response({"error": "Invalid merchant ID"}, status=400)
        
        # Get orders for this merchant
        orders = Order.objects.filter(
            merchant_id=merchant_id
        ).order_by('-created_at')
        
        # Serialize the orders
        serializer = OrderSerializer(orders, many=True)
        
        return Response({
            'success': True,
            'count': orders.count(),
            'orders': serializer.data
        })
        
    except Exception as e:
        print(f"🔥 Error in get_merchant_orders: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=500)
@api_view(['GET'])
def get_unpaid_orders(request):
    """
    Get orders that haven't been paid yet for a customer
    """
    try:
        customer_id = request.GET.get('customer_id')
        customer_type = request.GET.get('customer_type')
        
        if not customer_id or not customer_type:
            return Response({"error": "Customer ID and type required"}, status=400)
        
        # Convert customer_id to integer
        try:
            customer_id = int(customer_id)
        except ValueError:
            return Response({"error": "Invalid customer ID"}, status=400)
        
        print(f"🔍 Looking for unpaid orders for customer {customer_id} ({customer_type})")
        
        # Get orders that are NOT paid AND not cancelled
        # Include ALL statuses except 'cancelled'
        orders = Order.objects.filter(
            customer_id=customer_id,
            customer_type=customer_type,
            is_paid=False  # Only unpaid orders
        ).exclude(
            status='cancelled'  # Exclude cancelled orders
        ).order_by('-created_at')
        
        print(f"✅ Found {orders.count()} unpaid orders for customer {customer_id}")
        
        # Debug: Print order statuses
        status_summary = {}
        for order in orders:
            status = order.status
            status_summary[status] = status_summary.get(status, 0) + 1
            print(f"   - Order #{order.order_number}: status={order.status}, is_paid={order.is_paid}")
        
        print(f"📊 Status summary: {status_summary}")
        
        serializer = OrderSerializer(orders, many=True)
        
        return Response({
            'success': True,
            'count': orders.count(),
            'customer_id': customer_id,
            'customer_type': customer_type,
            'status_summary': status_summary,
            'orders': serializer.data
        })
        
    except Exception as e:
        print(f"🔥 Error in get_unpaid_orders: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=500)
@api_view(['POST'])
def cancel_order(request):
    """
    Cancel an order
    """
    try:
        order_id = request.data.get('order_id')
        customer_id = request.data.get('customer_id')
        customer_type = request.data.get('customer_type')
        
        if not order_id or not customer_id or not customer_type:
            return Response({"error": "Order ID, customer ID and type required"}, status=400)
        
        try:
            order = Order.objects.get(
                orderid=int(order_id),
                customer_id=int(customer_id),
                customer_type=customer_type
            )
            
            # Only allow cancellation for pending or delivered orders
            if order.status not in ['pending', 'delivered']:
                return Response({
                    "error": f"Cannot cancel order with status: {order.status}"
                }, status=400)
            
            order.status = 'cancelled'
            order.save()
            
            # Create notification
            Notification.objects.create(
                title=f"Order #{order.order_number} Cancelled",
                content=f"Order #{order.order_number} has been cancelled by {order.customer_name}",
                urgency="medium",
                designated_to="merchant",
                date=datetime.now()
            )
            
            serializer = OrderSerializer(order)
            
            return Response({
                'success': True,
                'message': 'Order cancelled successfully',
                'order': serializer.data
            })
            
        except Order.DoesNotExist:
            return Response({"error": "Order not found"}, status=404)
        
    except Exception as e:
        print(f"🔥 Error in cancel_order: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=500)

@api_view(['POST'])
def mark_order_paid(request):
    """
    Mark an order as paid
    """
    try:
        order_id = request.data.get('order_id')
        transaction_id = request.data.get('transaction_id')
        tip_amount = request.data.get('tip_amount', 0)
        message = request.data.get('message', '')
        
        if not order_id or not transaction_id:
            return Response({"error": "Order ID and transaction ID required"}, status=400)
        
        try:
            order = Order.objects.get(orderid=int(order_id))
            
            # Check if already paid
            if order.is_paid:
                return Response({
                    "success": True,
                    "message": "Order already paid",
                    "order": OrderSerializer(order).data
                })
            
            # Mark order as paid
            order.is_paid = True
            order.payment_date = datetime.now()
            order.transaction_id = transaction_id
            order.tip_amount = Decimal(str(tip_amount))
            order.customer_message = message
            order.save()
            
            # Create sales record
            items = order.get_items_list()
            for item in items:
                Sales.objects.create(
                    merchantid=order.merchant_id,
                    productname=item.get('productname', 'Unknown'),
                    amount=Decimal(str(item.get('price', 0))) * Decimal(str(item.get('quantity', 1))),
                    quantity=item.get('quantity', 1)
                )
            
            # Create notification
            Notification.objects.create(
                title=f"Order #{order.order_number} Paid",
                content=f"Order #{order.order_number} has been paid by {order.customer_name}. Amount: {order.total_amount} RWF",
                urgency="medium",
                designated_to="merchant",
                date=datetime.now()
            )
            
            # Also create notification for customer
            Notification.objects.create(
                title=f"Payment Confirmation",
                content=f"Payment for order #{order.order_number} to {order.merchant_name} has been completed.",
                urgency="low",
                designated_to=order.customer_type,
                date=datetime.now()
            )
            
            serializer = OrderSerializer(order)
            
            return Response({
                'success': True,
                'message': 'Order marked as paid',
                'order': serializer.data
            })
            
        except Order.DoesNotExist:
            return Response({"error": "Order not found"}, status=404)
        
    except Exception as e:
        print(f"🔥 Error in mark_order_paid: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=500)
@api_view(['GET'])
def get_merchant_order_notifications(request):
    """
    Get order notifications for a specific merchant
    """
    try:
        merchant_id = request.GET.get('merchant_id')
        
        if not merchant_id:
            return Response({"error": "Merchant ID required"}, status=400)
        
        try:
            merchant_id = int(merchant_id)
        except ValueError:
            return Response({"error": "Invalid merchant ID"}, status=400)
        
        # CRITICAL: Verify merchant exists
        try:
            merchant = Merchant.objects.get(merchantid=merchant_id)
        except Merchant.DoesNotExist:
            return Response({"error": "Merchant not found"}, status=404)
        
        print(f"🔍 Fetching orders for merchant ID: {merchant_id} ({merchant.username})")
        
        # Get orders for this specific merchant only
        orders = Order.objects.filter(
            merchant_id=merchant_id,
            status__in=['pending', 'confirmed', 'preparing', 'ready']
        ).order_by('-created_at')[:20]
        
        print(f"✅ Found {orders.count()} orders for merchant {merchant.username}")
        
        # Convert orders to notification format
        order_notifications = []
        for order in orders:
            # Debug: Check if order belongs to this merchant
            if order.merchant_id != merchant_id:
                print(f"⚠️ Warning: Order {order.orderid} has merchant_id={order.merchant_id}, expected {merchant_id}")
                continue
                
            notification = {
                'title': f"Order #{order.order_number} - {order.status.upper()}",
                'content': f"Order from {order.customer_name}. Total: {order.total_amount} RWF",
                'urgency': 'high' if order.status == 'pending' else 'medium',
                'date': order.created_at.isoformat() if order.created_at else datetime.now().isoformat(),
                'designated_to': 'merchant',
                'order_id': order.orderid,
                'order_number': order.order_number,
                'order_status': order.status,
                'customer_name': order.customer_name,
                'customer_id': order.customer_id,
                'total_amount': float(order.total_amount),
                'items': order.get_items_list(),
                'table_name': order.table_name or '',
                'is_paid': order.is_paid,
            }
            order_notifications.append(notification)
        
        return Response({
            'success': True,
            'count': len(order_notifications),
            'merchant_id': merchant_id,
            'merchant_name': merchant.username,
            'notifications': order_notifications
        })
        
    except Exception as e:
        print(f"🔥 Error in get_merchant_order_notifications: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=500)
@api_view(['POST'])
def update_order_status(request):
    """
    Update order status (for merchants)
    """
    try:
        order_id = request.data.get('order_id')
        new_status = request.data.get('status')
        merchant_id = request.data.get('merchant_id')
        
        if not order_id or not new_status or not merchant_id:
            return Response({"error": "Order ID, status and merchant ID required"}, status=400)
        
        valid_statuses = ['pending', 'confirmed', 'preparing', 'ready', 'delivered', 'cancelled']
        
        if new_status not in valid_statuses:
            return Response({"error": f"Invalid status. Must be one of: {valid_statuses}"}, status=400)
        
        try:
            order = Order.objects.get(
                orderid=int(order_id),
                merchant_id=int(merchant_id)  # Ensure merchant can only update their own orders
            )
            
            old_status = order.status
            order.status = new_status
            order.updated_at = timezone.now()
            order.save()
            
            # Create notification for customer about status change
            status_messages = {
                'confirmed': 'Your order has been confirmed',
                'preparing': 'Your order is being prepared',
                'ready': 'Your order is ready for pickup',
                'delivered': 'Your order has been delivered',
                'cancelled': 'Your order has been cancelled'
            }
            
            if new_status in status_messages:
                Notification.objects.create(
                    title=f"Order #{order.order_number} Update",
                    content=f"{status_messages[new_status]} by {order.merchant_name}",
                    urgency="medium",
                    designated_to=order.customer_type,
                    date=timezone.now()
                )
            
            # Also create notification for merchant
            Notification.objects.create(
                title=f"Order #{order.order_number} Status Updated",
                content=f"You changed order status from {old_status} to {new_status}",
                urgency="low",
                designated_to="merchant",
                date=timezone.now()
            )
            
            serializer = OrderSerializer(order)
            
            return Response({
                'success': True,
                'message': f'Order status updated from {old_status} to {new_status}',
                'order': serializer.data
            })
            
        except Order.DoesNotExist:
            return Response({"error": "Order not found or not authorized"}, status=404)
        except Exception as e:
            print(f"Error updating order: {str(e)}")
            return Response({"error": str(e)}, status=500)
        
    except Exception as e:
        print(f"🔥 Error in update_order_status: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=500)
# Add this new endpoint for payable orders
@api_view(['GET'])
def get_payable_orders(request):
    """
    Get all orders that can be paid by a customer
    (Orders that are not paid and not cancelled)
    """
    try:
        customer_id = request.GET.get('customer_id')
        customer_type = request.GET.get('customer_type')
        
        if not customer_id or not customer_type:
            return Response({"error": "Customer ID and type required"}, status=400)
        
        try:
            customer_id = int(customer_id)
        except ValueError:
            return Response({"error": "Invalid customer ID"}, status=400)
        
        print(f"🔍 Looking for payable orders for customer {customer_id} ({customer_type})")
        
        # Get orders that can be paid:
        # 1. Not paid (is_paid = False)
        # 2. Not cancelled
        # 3. Any status except 'cancelled' (pending, confirmed, preparing, ready, delivered)
        payable_orders = Order.objects.filter(
            customer_id=customer_id,
            customer_type=customer_type,
            is_paid=False  # Not paid yet
        ).exclude(
            status='cancelled'  # Exclude cancelled orders
        ).order_by('-created_at')
        
        print(f"✅ Found {payable_orders.count()} payable orders")
        
        # Group orders by status for debugging
        status_counts = payable_orders.values('status').annotate(count=models.Count('status'))
        for stat in status_counts:
            print(f"   - Status {stat['status']}: {stat['count']} orders")
        
        serializer = OrderSerializer(payable_orders, many=True)
        
        return Response({
            'success': True,
            'count': payable_orders.count(),
            'customer_id': customer_id,
            'customer_type': customer_type,
            'status_breakdown': {s['status']: s['count'] for s in status_counts},
            'orders': serializer.data
        })
        
    except Exception as e:
        print(f"🔥 Error in get_payable_orders: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({'error': str(e)}, status=500)
    
@api_view(['POST'])
def verify_pin(request):
    """
    Verify user's PIN
    """
    try:
        email = request.data.get('email')

        pin = request.data.get('pin')
        
        if not email or not pin:
            return Response({"success": False, "error": "Email and PIN required"}, status=400)
        
        print(f"🔍 Verifying PIN for email: {email}")
        
        # Check Users
        try:
            user = User.objects.get(email=email)
            if str(user.pin) == str(pin):
                return Response({
                    "success": True,
                    "message": "PIN verified",
                    "type": "user"
                })
        except User.DoesNotExist:
            pass
        
        # Check Merchants
        try:
            merchant = Merchant.objects.get(email=email)
            if str(merchant.pin) == str(pin):
                return Response({
                    "success": True,
                    "message": "PIN verified",
                    "type": "merchant"
                })
        except Merchant.DoesNotExist:
            pass
        
        return Response({
            "success": False,
            "error": "Invalid PIN or user not found"
        }, status=400)
        
    except Exception as e:
        print(f"🔥 Error in verify_pin: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({"success": False, "error": str(e)}, status=500)

# In your views.py, replace all admin views with this single view:

from django.shortcuts import render
from django.db.models import Count, Sum, Q
from datetime import datetime, timedelta
import json

def admin_dashboard(request):
    """Single comprehensive admin dashboard"""
    # Get all statistics
    from .models import User, Merchant, Order, Transaction, Product, Notification, Sales, Menu
    
    # Basic counts
    total_users = User.objects.count()
    total_merchants = Merchant.objects.count()
    total_orders = Order.objects.count()
    total_products = Product.objects.count()
    total_transactions = Transaction.objects.count()
    
    # Today's stats
    today = datetime.now().date()
    orders_today = Order.objects.filter(created_at__date=today).count()
    
    # Revenue calculations
    total_revenue = Transaction.objects.aggregate(total=Sum('amount'))['total'] or 0
    revenue_today = Transaction.objects.filter(date__date=today).aggregate(total=Sum('amount'))['total'] or 0
    
    # Recent data for display
    recent_users = User.objects.all().order_by('-userid')[:10]
    recent_merchants = Merchant.objects.all().order_by('-merchantid')[:10]
    recent_orders = Order.objects.all().order_by('-created_at')[:10]
    recent_transactions = Transaction.objects.all().order_by('-date')[:10]
    recent_products = Product.objects.all().order_by('-productid')[:10]
    
    # Status counts for orders
    order_status_counts = Order.objects.values('status').annotate(count=Count('status'))
    
    # Top merchants by revenue
    top_merchants = []
    merchants = Merchant.objects.all()[:10]
    for merchant in merchants:
        revenue = Transaction.objects.filter(
            receiverid=merchant.merchantid,
            receiver_type='merchant'
        ).aggregate(total=Sum('amount'))['total'] or 0
        
        order_count = Order.objects.filter(merchant_id=merchant.merchantid).count()
        product_count = Product.objects.filter(merchantid=merchant.merchantid).count()
        
        top_merchants.append({
            'id': merchant.merchantid,
            'name': merchant.username,
            'email': merchant.email,
            'revenue': revenue,
            'orders': order_count,
            'products': product_count
        })
    
    # Daily revenue for last 7 days (for charts)
    daily_revenue = []
    for i in range(7):
        date = today - timedelta(days=i)
        revenue = Transaction.objects.filter(
            date__date=date  # This is fine because Transaction.date is DateTimeField
        ).aggregate(total=Sum('amount'))['total'] or 0
        
        daily_revenue.append({
            'date': date.isoformat(),
            'revenue': float(revenue)
        })
    
    # FIXED: User growth for last 7 days - Remove date__lte for DateField
    user_growth = []
    for i in range(7):
        date = today - timedelta(days=i)
        
        # For DateField, just use __lte without date__
        user_count = User.objects.filter(
            dateofbirth__lte=date
        ).count()
        
        merchant_count = Merchant.objects.filter(
            dateofcreation__lte=date
        ).count()
        
        user_growth.append({
            'date': date.isoformat(),
            'users': user_count,
            'merchants': merchant_count
        })
    
    # System notifications
    system_notifications = Notification.objects.all().order_by('-date')[:20]
    
    # Prepare data for charts (simplified for now)
    order_status_data = {
        'labels': [],
        'data': []
    }
    for status in order_status_counts:
        order_status_data['labels'].append(status['status'])
        order_status_data['data'].append(status['count'])
    
    # User distribution data
    user_distribution_data = {
        'labels': ['Users', 'Merchants'],
        'data': [total_users, total_merchants]
    }
    
    context = {
        'total_users': total_users,
        'total_merchants': total_merchants,
        'total_orders': total_orders,
        'total_products': total_products,
        'total_transactions': total_transactions,
        'orders_today': orders_today,
        'total_revenue': total_revenue,
        'revenue_today': revenue_today,
        'today': today,
        
        # Recent data
        'recent_users': recent_users,
        'recent_merchants': recent_merchants,
        'recent_orders': recent_orders,
        'recent_transactions': recent_transactions,
        'recent_products': recent_products,
        'system_notifications': system_notifications,
        
        # Analytics
        'order_status_counts': list(order_status_counts),
        'top_merchants': top_merchants,
        'daily_revenue': daily_revenue,
        'user_growth': user_growth,
        
        # For charts
        'order_status_data': json.dumps(order_status_data),
        'user_distribution_data': json.dumps(user_distribution_data),
    }
    
    return render(request, 'api/admin_dashboard.html', context)

# API endpoints for admin data
from rest_framework.decorators import api_view
from rest_framework.response import Response

@api_view(['GET'])
def get_dashboard_stats(request):
    """API endpoint for dashboard statistics"""
    from .models import User, Merchant, Order, Transaction
    from datetime import datetime, timedelta
    
    today = datetime.now().date()
    yesterday = today - timedelta(days=1)
    
    # Get counts
    stats = {
        'total_users': User.objects.count(),
        'total_merchants': Merchant.objects.count(),
        'total_orders': Order.objects.count(),
        'orders_today': Order.objects.filter(created_at__date=today).count(),
        'orders_yesterday': Order.objects.filter(created_at__date=yesterday).count(),
        'total_revenue': Transaction.objects.aggregate(total=Sum('amount'))['total'] or 0,
        'revenue_today': Transaction.objects.filter(date__date=today).aggregate(total=Sum('amount'))['total'] or 0,
        'active_users': User.objects.filter(balance__gt=0).count(),
        'active_merchants': Merchant.objects.filter(balance__gt=0).count(),
    }
    
    # Get recent activity
    recent_transactions = Transaction.objects.order_by('-date')[:10].values(
        'transactionid', 'senderid', 'receiverid', 'amount', 'date'
    )
    stats['recent_transactions'] = list(recent_transactions)
    
    return Response(stats)

@api_view(['GET'])
def get_user_details_api(request):
    """API endpoint for user details"""
    user_id = request.GET.get('user_id')
    user_type = request.GET.get('user_type', 'user')
    
    from .models import User, Merchant, Transaction, Order
    
    if user_type == 'user':
        try:
            user = User.objects.get(userid=user_id)
            transactions = Transaction.objects.filter(
                Q(senderid=user_id, sender_type='user') |
                Q(receiverid=user_id, receiver_type='user')
            ).order_by('-date')[:20]
            
            orders = Order.objects.filter(
                customer_id=user_id,
                customer_type='user'
            ).order_by('-created_at')[:10]
            
            return Response({
                'user': {
                    'id': user.userid,
                    'username': user.username,
                    'email': user.email,
                    'phone': user.phonenumber,
                    'balance': user.balance,
                    'national_id': user.nationalid,
                    'paycode': user.paycode,
                    'date_joined': user.dateofbirth,
                },
                'transactions': list(transactions.values()),
                'orders': list(orders.values()),
            })
        except User.DoesNotExist:
            return Response({'error': 'User not found'}, status=404)
    
    else:  # merchant
        try:
            merchant = Merchant.objects.get(merchantid=user_id)
            transactions = Transaction.objects.filter(
                Q(senderid=user_id, sender_type='merchant') |
                Q(receiverid=user_id, receiver_type='merchant')
            ).order_by('-date')[:20]
            
            orders = Order.objects.filter(merchant_id=user_id).order_by('-created_at')[:10]
            
            from .models import Product
            products = Product.objects.filter(merchantid=user_id)[:20]
            
            return Response({
                'merchant': {
                    'id': merchant.merchantid,
                    'username': merchant.username,
                    'email': merchant.email,
                    'phone': merchant.phonenumber,
                    'balance': merchant.balance,
                    'business_type': merchant.businesstype,
                    'merchant_paycode': merchant.merchantpaycode,
                    'date_created': merchant.dateofcreation,
                },
                'transactions': list(transactions.values()),
                'orders': list(orders.values()),
                'products': list(products.values()),
            })
        except Merchant.DoesNotExist:
            return Response({'error': 'Merchant not found'}, status=404)

@api_view(['POST'])
def create_user_admin(request):
    """API endpoint to create user from admin"""
    try:
        from .models import User
        from .utils import generate_user_paycode
        
        data = request.data
        
        user = User.objects.create(
            nationalid=data.get('national_id'),
            paycode=generate_user_paycode(),
            accounttype='normal',
            email=data.get('email'),
            username=data.get('username'),
            phonenumber=data.get('phone'),
            password=data.get('password'),
            dateofbirth=data.get('date_of_birth'),
            balance=data.get('balance', 5000.00),
            pin=data.get('pin', '123456')
        )
        
        return Response({
            'success': True,
            'message': 'User created successfully',
            'user_id': user.userid
        })
        
    except Exception as e:
        return Response({'error': str(e)}, status=400)

@api_view(['POST'])
def create_merchant_admin(request):
    """API endpoint to create merchant from admin"""
    try:
        from .models import Merchant
        from .utils import generate_merchant_paycode
        
        data = request.data
        
        merchant = Merchant.objects.create(
            nationalid=data.get('national_id'),
            merchantpaycode=generate_merchant_paycode(),
            businesstype=data.get('business_type'),
            accounttype='merchant',
            email=data.get('email'),
            username=data.get('username'),
            phonenumber=data.get('phone'),
            password=data.get('password'),
            dateofcreation=data.get('date_of_creation'),
            balance=data.get('balance', 5000.00),
            pin=data.get('pin', '123456')
        )
        
        return Response({
            'success': True,
            'message': 'Merchant created successfully',
            'merchant_id': merchant.merchantid
        })
        
    except Exception as e:
        return Response({'error': str(e)}, status=400)

@api_view(['PUT'])
def update_user_balance(request):
    """API endpoint to update user/merchant balance"""
    try:
        user_id = request.data.get('user_id')
        user_type = request.data.get('user_type')
        amount = request.data.get('amount')
        operation = request.data.get('operation', 'add')  # 'add' or 'subtract'
        
        if user_type == 'user':
            from .models import User
            user = User.objects.get(userid=user_id)
        else:
            from .models import Merchant
            user = Merchant.objects.get(merchantid=user_id)
        
        if operation == 'add':
            user.balance += float(amount)
        else:
            user.balance -= float(amount)
        
        user.save()
        
        return Response({
            'success': True,
            'message': f'Balance updated successfully',
            'new_balance': user.balance
        })
        
    except Exception as e:
        return Response({'error': str(e)}, status=400)

@api_view(['GET'])
def get_system_analytics(request):
    """API endpoint for system analytics"""
    from .models import Order, Transaction, User, Merchant
    from datetime import datetime, timedelta
    import json
    
    # Get date range (last 30 days)
    end_date = datetime.now().date()
    start_date = end_date - timedelta(days=30)
    
    # Daily revenue for last 30 days
    daily_revenue = []
    for i in range(30):
        date = end_date - timedelta(days=i)
        revenue = Transaction.objects.filter(
            date__date=date
        ).aggregate(total=Sum('amount'))['total'] or 0
        daily_revenue.append({
            'date': date.isoformat(),
            'revenue': float(revenue)
        })
    
    # Order status distribution
    order_status = Order.objects.values('status').annotate(
        count=Count('status')
    )
    
    # User growth (last 7 days)
    user_growth = []
    for i in range(7):
        date = end_date - timedelta(days=i)
        user_count = User.objects.filter(
            dateofbirth__date__lte=date
        ).count()
        merchant_count = Merchant.objects.filter(
            dateofcreation__date__lte=date
        ).count()
        user_growth.append({
            'date': date.isoformat(),
            'users': user_count,
            'merchants': merchant_count
        })
    
    # Top merchants by revenue
    top_merchants = []
    merchants = Merchant.objects.all()[:10]
    for merchant in merchants:
        revenue = Transaction.objects.filter(
            receiverid=merchant.merchantid,
            receiver_type='merchant'
        ).aggregate(total=Sum('amount'))['total'] or 0
        top_merchants.append({
            'name': merchant.username,
            'revenue': float(revenue),
            'orders': Order.objects.filter(merchant_id=merchant.merchantid).count()
        })
    
    return Response({
        'daily_revenue': daily_revenue,
        'order_status': list(order_status),
        'user_growth': user_growth,
        'top_merchants': top_merchants,
        'timeframe': {
            'start_date': start_date.isoformat(),
            'end_date': end_date.isoformat()
        }
    })
@csrf_exempt
def create_entry(request):
    """Generic create endpoint for all models"""
    if request.method == "POST":
        try:
            data = request.POST
            entry_type = data.get('type')
            
            if entry_type == 'user':
                from .utils import generate_user_paycode
                user = User.objects.create(
                    nationalid=data.get('national_id'),
                    paycode=generate_user_paycode(),
                    accounttype='normal',
                    email=data.get('email'),
                    username=data.get('username'),
                    phonenumber=data.get('phone'),
                    password=data.get('password'),
                    pin=data.get('pin', '123456'),
                    balance=data.get('balance', 5000.00)
                )
                return JsonResponse({
                    "success": True,
                    "message": "User created successfully",
                    "id": user.userid
                })
                
            elif entry_type == 'merchant':
                from .utils import generate_merchant_paycode
                merchant = Merchant.objects.create(
                    nationalid=data.get('national_id'),
                    merchantpaycode=generate_merchant_paycode(),
                    businesstype=data.get('business_type'),
                    accounttype='merchant',
                    email=data.get('email'),
                    username=data.get('username'),
                    phonenumber=data.get('phone'),
                    password=data.get('password'),
                    pin=data.get('pin', '123456'),
                    balance=data.get('balance', 5000.00)
                )
                return JsonResponse({
                    "success": True,
                    "message": "Merchant created successfully",
                    "id": merchant.merchantid
                })
                
            elif entry_type == 'product':
                import random
                from datetime import datetime
                product = Product.objects.create(
                    productid=int(datetime.now().timestamp() * 1000) + random.randint(1000, 9999),
                    productname=data.get('product_name'),
                    price=data.get('price'),
                    amountinstock=data.get('amount_in_stock'),
                    category=data.get('category'),
                    merchantid=data.get('merchant_id')
                )
                return JsonResponse({
                    "success": True,
                    "message": "Product created successfully",
                    "id": product.productid
                })
                
            elif entry_type == 'service':
                service = ExtraMenu.objects.create(
                    fieldname=data.get('fieldname'),
                    merchantid=data.get('merchantid')
                )
                return JsonResponse({
                    "success": True,
                    "message": "Service created successfully",
                    "id": service.id
                })
                
            return JsonResponse({
                "success": False,
                "message": "Invalid entry type"
            }, status=400)
            
        except Exception as e:
            return JsonResponse({
                "success": False,
                "message": str(e)
            }, status=400)

@csrf_exempt
def delete_entry(request, entry_type, entry_id):
    """Generic delete endpoint for all models"""
    if request.method == "DELETE":
        try:
            if entry_type == 'user':
                user = get_object_or_404(User, userid=entry_id)
                user.delete()
                
            elif entry_type == 'merchant':
                merchant = get_object_or_404(Merchant, merchantid=entry_id)
                merchant.delete()
                
            elif entry_type == 'product':
                product = get_object_or_404(Product, productid=entry_id)
                product.delete()
                
            elif entry_type == 'service':
                service = get_object_or_404(ExtraMenu, id=entry_id)
                service.delete()
                
            elif entry_type == 'order':
                order = get_object_or_404(Order, orderid=entry_id)
                order.delete()
                
            else:
                return JsonResponse({
                    "success": False,
                    "message": "Invalid entry type"
                }, status=400)
                
            return JsonResponse({
                "success": True,
                "message": f"{entry_type.capitalize()} deleted successfully"
            })
            
        except Exception as e:
            return JsonResponse({
                "success": False,
                "message": str(e)
            }, status=400)
    
    return JsonResponse({
        "success": False,
        "message": "Method not allowed"
    }, status=405)
logger = logging.getLogger(__name__)

@csrf_exempt
def admin_dashboard(request):
    """Single comprehensive admin dashboard with all data"""
    try:
        # Get all data from database
        users = User.objects.all()
        merchants = Merchant.objects.all()
        orders = Order.objects.all()
        services = ExtraMenu.objects.all()
        products = Product.objects.all()
        transactions = Transaction.objects.all()
        menus = Menu.objects.all()
        
        # Get counts for analytics
        total_users = users.count()
        total_merchants = merchants.count()
        total_orders = orders.count()
        total_products = products.count()
        total_transactions = transactions.count()
        total_services = services.count()
        
        # Today's stats
        today = datetime.now().date()
        orders_today = Order.objects.filter(created_at__date=today).count()
        
        # Revenue calculations
        total_revenue = Transaction.objects.aggregate(total=Sum('amount'))['total'] or 0
        revenue_today = Transaction.objects.filter(date__date=today).aggregate(total=Sum('amount'))['total'] or 0
        
        context = {
            # All data for tables
            'users': users,
            'merchants': merchants,
            'orders': orders,
            'services': services,
            'products': products,
            'transactions': transactions,
            'menus': menus,
            
            # Analytics counts
            'users_count': total_users,
            'merchants_count': total_merchants,
            'orders_count': total_orders,
            'products_count': total_products,
            'transactions_count': total_transactions,
            'services_count': total_services,
            
            # Additional stats
            'orders_today': orders_today,
            'total_revenue': total_revenue,
            'revenue_today': revenue_today,
            'today': today,
        }
        
        return render(request, 'api/admin_dashboard.html', context)
        
    except Exception as e:
        print(f"Error in admin_dashboard: {str(e)}")
        import traceback
        traceback.print_exc()
        # Return empty context if there's an error
        return render(request, 'api/admin_dashboard.html', {
            'users': [],
            'merchants': [],
            'orders': [],
            'services': [],
            'products': [],
            'transactions': [],
            'menus': [],
            'users_count': 0,
            'merchants_count': 0,
            'orders_count': 0,
            'products_count': 0,
            'transactions_count': 0,
            'services_count': 0,
            'error': str(e)
        })

# Add the missing functions that are referenced in URLs
@csrf_exempt
def create_product_admin(request):
    """Admin endpoint to create product"""
    if request.method == "POST":
        try:
            data = request.POST
            import random
            from datetime import datetime
            
            # Generate product ID
            product_id = int(datetime.now().timestamp() * 1000) + random.randint(1000, 9999)
            
            product = Product.objects.create(
                productid=product_id,
                productname=data.get('product_name'),
                price=Decimal(data.get('price', 0)),
                amountinstock=int(data.get('amount_in_stock', 0)),
                category=data.get('category', ''),
                merchantid=int(data.get('merchant_id', 0))
            )
            
            return JsonResponse({
                "success": True,
                "message": "Product created successfully",
                "id": product.productid
            })
            
        except Exception as e:
            return JsonResponse({
                "success": False,
                "message": str(e)
            }, status=400)
    
    return JsonResponse({
        "success": False,
        "message": "Method not allowed"
    }, status=405)

@csrf_exempt
def create_service_admin(request):
    """Admin endpoint to create service (ExtraMenu)"""
    if request.method == "POST":
        try:
            data = request.POST
            
            service = ExtraMenu.objects.create(
                fieldname=data.get('fieldname', ''),
                merchantid=int(data.get('merchantid', 0))
            )
            
            return JsonResponse({
                "success": True,
                "message": "Service created successfully",
                "id": service.id
            })
            
        except Exception as e:
            return JsonResponse({
                "success": False,
                "message": str(e)
            }, status=400)
    
    return JsonResponse({
        "success": False,
        "message": "Method not allowed"
    }, status=405)
# Add these imports at the TOP of your views.py if not already there:
from django.db.models import Q, Sum, Count
from decimal import Decimal
import os
from datetime import datetime
from io import BytesIO
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, Image
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib import colors
from reportlab.lib.units import inch
from django.http import HttpResponse
from django.conf import settings

# Update the generate_merchant_report function with better error handling:
@api_view(['GET'])
def generate_merchant_report(request):
    """
    Generate comprehensive PDF report for a merchant
    """
    try:
        # Get parameters
        merchant_id = request.GET.get('merchant_id')
        year = request.GET.get('year')
        month = request.GET.get('month')
        day = request.GET.get('day')
        
        print(f"📊 Generating report for merchant_id: {merchant_id}, year: {year}, month: {month}, day: {day}")
        
        if not merchant_id:
            return Response({"error": "Merchant ID is required"}, status=400)
        
        # Get merchant details
        try:
            merchant = Merchant.objects.get(merchantid=int(merchant_id))
            print(f"✅ Found merchant: {merchant.username}")
        except Merchant.DoesNotExist:
            print(f"❌ Merchant not found: {merchant_id}")
            return Response({"error": "Merchant not found"}, status=404)
        except ValueError:
            print(f"❌ Invalid merchant ID format: {merchant_id}")
            return Response({"error": "Invalid merchant ID format"}, status=400)
        
        # Create response with PDF
        response = HttpResponse(content_type='application/pdf')
        filename = f"merchant_report_{merchant.username}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        
        # Create PDF buffer
        buffer = BytesIO()
        
        try:
            # Create the PDF document
            doc = SimpleDocTemplate(buffer, pagesize=A4, 
                                   rightMargin=72, leftMargin=72,
                                   topMargin=72, bottomMargin=72)
            
            # Container for the 'Flowable' objects
            elements = []
            
            # Get styles
            styles = getSampleStyleSheet()
            
            # Custom styles
            title_style = ParagraphStyle(
                'CustomTitle',
                parent=styles['Heading1'],
                fontSize=24,
                spaceAfter=30,
                alignment=TA_CENTER,
                textColor=colors.HexColor('#FF8A00')
            )
            
            normal_style = ParagraphStyle(
                'Normal',
                parent=styles['Normal'],
                fontSize=10
            )
            
            # Add title
            elements.append(Paragraph("MERCHANT BUSINESS REPORT", title_style))
            
            # Add merchant info
            merchant_info = f"""
            <b>Merchant:</b> {merchant.username}<br/>
            <b>Email:</b> {merchant.email}<br/>
            <b>Phone:</b> {merchant.phonenumber or 'N/A'}<br/>
            <b>Business Type:</b> {merchant.businesstype or 'N/A'}<br/>
            <b>Merchant ID:</b> {merchant.merchantid}<br/>
            <b>Report Date:</b> {datetime.now().strftime('%d %B %Y %H:%M:%S')}<br/>
            """
            
            if year:
                merchant_info += f"<b>Year:</b> {year}<br/>"
            if month:
                merchant_info += f"<b>Month:</b> {month}<br/>"
            if day:
                merchant_info += f"<b>Day:</b> {day}<br/>"
            
            elements.append(Paragraph(merchant_info, normal_style))
            elements.append(Spacer(1, 20))
            
            # ================ SECTION 1: FINANCIAL SUMMARY ================
            section_style = ParagraphStyle(
                'Section',
                parent=styles['Heading3'],
                fontSize=12,
                spaceAfter=10,
                spaceBefore=20,
                textColor=colors.HexColor('#2C3E50')
            )
            
            elements.append(Paragraph("1. FINANCIAL SUMMARY", section_style))
            
            # Get date range for filtering
            date_filter = Q()
            if year:
                date_filter &= Q(date__year=int(year))
            if month:
                date_filter &= Q(date__month=int(month))
            if day:
                date_filter &= Q(date__day=int(day))
            
            print(f"📅 Applying date filter: {date_filter}")
            
            # Get all transactions for this merchant
            all_transactions = Transaction.objects.filter(
                (Q(senderid=merchant.merchantid) & Q(sender_type='merchant')) |
                (Q(receiverid=merchant.merchantid) & Q(receiver_type='merchant'))
            )
            
            if date_filter:
                all_transactions = all_transactions.filter(date_filter)
            
            all_transactions = all_transactions.order_by('date')
            
            print(f"💰 Found {all_transactions.count()} transactions")
            
            # Calculate totals
            total_income = Decimal('0.00')
            total_expenses = Decimal('0.00')
            total_received = Decimal('0.00')
            total_sent = Decimal('0.00')
            
            for trans in all_transactions:
                if trans.receiverid == merchant.merchantid and trans.receiver_type == 'merchant':
                    # Income (money received)
                    if trans.amount:
                        total_income += Decimal(str(trans.amount))
                        total_received += Decimal(str(trans.amount))
                elif trans.senderid == merchant.merchantid and trans.sender_type == 'merchant':
                    # Expense (money sent)
                    if trans.amount:
                        total_expenses += Decimal(str(trans.amount))
                        total_sent += Decimal(str(trans.amount))
                    if trans.charge:
                        total_expenses += Decimal(str(trans.charge))
            
            current_balance = merchant.balance if merchant.balance else Decimal('0.00')
            net_profit = total_income - total_expenses
            
            # Financial summary table
            financial_data = [
                ['Description', 'Amount (RWF)'],
                ['Current Balance', f"{float(current_balance):,.2f}"],
                ['Total Income', f"{float(total_income):,.2f}"],
                ['Total Expenses', f"{float(total_expenses):,.2f}"],
                ['Net Profit/Loss', f"{float(net_profit):,.2f}"],
                ['Total Received', f"{float(total_received):,.2f}"],
                ['Total Sent', f"{float(total_sent):,.2f}"],
            ]
            
            financial_table = Table(financial_data, colWidths=[3*inch, 2*inch])
            financial_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#FF8A00')),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('ALIGN', (0, 0), (-1, 0), 'CENTER'),
                ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                ('FONTSIZE', (0, 0), (-1, 0), 10),
                ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
                ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
                ('TEXTCOLOR', (0, 1), (-1, -1), colors.black),
                ('ALIGN', (0, 1), (0, -1), 'LEFT'),
                ('ALIGN', (1, 1), (1, -1), 'RIGHT'),
                ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
                ('FONTSIZE', (0, 1), (-1, -1), 10),
                ('GRID', (0, 0), (-1, -1), 1, colors.black),
            ]))
            
            elements.append(financial_table)
            elements.append(Spacer(1, 20))
            
            # ================ SECTION 2: PRODUCTS SALES SUMMARY ================
            elements.append(Paragraph("2. PRODUCTS SALES SUMMARY", section_style))
            
            # Get sales data
            sales = Sales.objects.filter(merchantid=merchant.merchantid)
            
            # Apply date filter to sales
            if date_filter:
                # Sales model uses 'date' field
                sales_date_filter = Q()
                if year:
                    sales_date_filter &= Q(date__year=int(year))
                if month:
                    sales_date_filter &= Q(date__month=int(month))
                if day:
                    sales_date_filter &= Q(date__day=int(day))
                sales = sales.filter(sales_date_filter)
            
            print(f"📈 Found {sales.count()} sales records")
            
            if sales.exists():
                # Create a dictionary to aggregate product sales
                product_sales = {}
                total_quantity_sold = 0
                total_sales_amount = Decimal('0.00')
                
                for sale in sales:
                    product_name = sale.productname
                    quantity = sale.quantity if sale.quantity else 0
                    amount = Decimal(str(sale.amount)) if sale.amount else Decimal('0.00')
                    
                    if product_name in product_sales:
                        product_sales[product_name]['quantity'] += quantity
                        product_sales[product_name]['amount'] += amount
                    else:
                        product_sales[product_name] = {
                            'quantity': quantity,
                            'amount': amount,
                            'unit_price': amount / quantity if quantity > 0 else Decimal('0.00')
                        }
                    
                    total_quantity_sold += quantity
                    total_sales_amount += amount
                
                # Sort products by amount (descending)
                sorted_products = sorted(
                    product_sales.items(),
                    key=lambda x: x[1]['amount'],
                    reverse=True
                )
                
                # Create sales summary table with fancy styling
                sales_data = [
                    ['Product Name', 'Quantity Sold', 'Total Amount (RWF)', 'Avg. Price']
                ]
                
                for product_name, data in sorted_products:
                    sales_data.append([
                        product_name[:25] if product_name else 'N/A',
                        str(data['quantity']),
                        f"{float(data['amount']):,.2f}",
                        f"{float(data['unit_price']):,.2f}"
                    ])
                
                # Add totals row
                if len(sorted_products) > 0:
                    sales_data.append([
                        '<b>TOTAL</b>',
                        f"<b>{total_quantity_sold}</b>",
                        f"<b>{float(total_sales_amount):,.2f}</b>",
                        ""
                    ])
                
                sales_table = Table(sales_data, colWidths=[2.5*inch, 1*inch, 1.5*inch, 1*inch])
                
                # Create fancy table style with alternating row colors
                sales_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#8E44AD')),  # Purple header
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, 0), 'CENTER'),
                    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 10),
                    ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
                    ('GRID', (0, 0), (-1, -1), 1, colors.black),
                ]))
                
                # Add alternating row colors
                for i in range(1, len(sales_data)):
                    if i == len(sales_data) - 1:  # Last row (totals)
                        sales_table.setStyle(TableStyle([
                            ('BACKGROUND', (0, i), (-1, i), colors.HexColor('#F39C12')),  # Orange for totals
                            ('TEXTCOLOR', (0, i), (-1, i), colors.whitesmoke),
                            ('FONTNAME', (0, i), (-1, i), 'Helvetica-Bold'),
                        ]))
                    elif i % 2 == 0:
                        sales_table.setStyle(TableStyle([
                            ('BACKGROUND', (0, i), (-1, i), colors.HexColor('#F8F9FA')),  # Light gray
                        ]))
                    else:
                        sales_table.setStyle(TableStyle([
                            ('BACKGROUND', (0, i), (-1, i), colors.white),
                        ]))
                    
                    # Set alignment for data rows
                    sales_table.setStyle(TableStyle([
                        ('ALIGN', (1, i), (1, i), 'CENTER'),  # Quantity center
                        ('ALIGN', (2, i), (2, i), 'RIGHT'),   # Amount right
                        ('ALIGN', (3, i), (3, i), 'RIGHT'),   # Price right
                        ('FONTSIZE', (0, i), (-1, i), 9),
                        ('PADDING', (0, i), (-1, i), (6, 4)),
                    ]))
                
                elements.append(sales_table)
                
                # Add sales summary statistics
                elements.append(Spacer(1, 10))
                stats_text = f"""
                <b>Sales Statistics:</b><br/>
                • Total Products Sold: {total_quantity_sold}<br/>
                • Total Sales Value: {float(total_sales_amount):,.2f} RWF<br/>
                • Average Sale Value: {float(total_sales_amount/total_quantity_sold if total_quantity_sold > 0 else 0):,.2f} RWF per unit<br/>
                • Number of Products Sold: {len(sorted_products)}<br/>
                """
                elements.append(Paragraph(stats_text, normal_style))
                
            else:
                elements.append(Paragraph("No sales data found for the selected period.", normal_style))
            
            elements.append(Spacer(1, 20))
            
            # ================ SECTION 3: ORDERS SUMMARY ================
            elements.append(Paragraph("3. ORDERS SUMMARY", section_style))
            
            # Get orders for this merchant
            orders = Order.objects.filter(merchant_id=merchant.merchantid)
            
            if date_filter:
                # Handle different date field names
                try:
                    orders = orders.filter(created_at__year=int(year))
                    if month:
                        orders = orders.filter(created_at__month=int(month))
                    if day:
                        orders = orders.filter(created_at__day=int(day))
                except:
                    pass  # If date filtering fails, show all orders
            
            orders = orders.order_by('-created_at')
            
            print(f"📦 Found {orders.count()} orders")
            
            if orders.exists():
                order_summary = f"""
                <b>Total Orders:</b> {orders.count()}<br/>
                <b>Pending Orders:</b> {orders.filter(status='pending').count()}<br/>
                <b>Completed Orders:</b> {orders.filter(status='delivered').count()}<br/>
                <b>Cancelled Orders:</b> {orders.filter(status='cancelled').count()}<br/>
                """
                
                # Calculate total order value
                total_order_value = Decimal('0.00')
                paid_orders_value = Decimal('0.00')
                
                for order in orders:
                    if order.total_amount:
                        total_order_value += Decimal(str(order.total_amount))
                        if order.is_paid:
                            paid_orders_value += Decimal(str(order.total_amount))
                
                order_summary += f"<b>Total Order Value:</b> {float(total_order_value):,.2f} RWF<br/>"
                order_summary += f"<b>Paid Orders Value:</b> {float(paid_orders_value):,.2f} RWF<br/>"
                order_summary += f"<b>Unpaid Orders Value:</b> {float(total_order_value - paid_orders_value):,.2f} RWF<br/>"
                
                elements.append(Paragraph(order_summary, normal_style))
                
                # Show recent orders in a table
                if orders.count() <= 20:  # Only show if not too many
                    order_data = [['Order #', 'Customer', 'Amount', 'Status', 'Paid']]
                    
                    for order in orders[:10]:  # Show first 10 orders
                        order_data.append([
                            order.order_number[:8] if order.order_number else 'N/A',
                            order.customer_name[:15] if order.customer_name else 'N/A',
                            f"{float(order.total_amount):,.2f}" if order.total_amount else '0.00',
                            order.status or 'N/A',
                            '✓' if order.is_paid else '✗'
                        ])
                    
                    order_table = Table(order_data, colWidths=[1*inch, 1.5*inch, 1*inch, 1*inch, 0.5*inch])
                    order_table.setStyle(TableStyle([
                        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#27AE60')),
                        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                        ('ALIGN', (0, 0), (-1, 0), 'CENTER'),
                        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                        ('FONTSIZE', (0, 0), (-1, 0), 9),
                        ('BOTTOMPADDING', (0, 0), (-1, 0), 6),
                        ('BACKGROUND', (0, 1), (-1, -1), colors.white),
                        ('TEXTCOLOR', (0, 1), (-1, -1), colors.black),
                        ('ALIGN', (0, 1), (-1, -1), 'LEFT'),
                        ('ALIGN', (4, 1), (4, -1), 'CENTER'),
                        ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
                        ('FONTSIZE', (0, 1), (-1, -1), 8),
                        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
                    ]))
                    
                    elements.append(order_table)
            else:
                elements.append(Paragraph("No orders found for the selected period.", normal_style))
            
            elements.append(Spacer(1, 20))
            
            # ================ SECTION 4: PRODUCTS IN MENU ================
            elements.append(Paragraph("4. PRODUCTS IN MENU", section_style))
            
            # Get products for this merchant
            products = Product.objects.filter(merchantid=merchant.merchantid)
            
            if products.exists():
                product_data = [['Product', 'Price (RWF)', 'In Stock', 'Category']]
                
                for product in products:
                    product_data.append([
                        product.productname[:25] if product.productname else 'N/A',
                        f"{float(product.price):,.2f}" if product.price else '0.00',
                        str(product.amountinstock) if product.amountinstock else '0',
                        product.category[:15] if product.category else 'N/A'
                    ])
                
                product_table = Table(product_data, colWidths=[2*inch, 1*inch, 0.8*inch, 1.2*inch])
                product_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#3498DB')),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, 0), 'CENTER'),
                    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 9),
                    ('BOTTOMPADDING', (0, 0), (-1, 0), 6),
                    ('BACKGROUND', (0, 1), (-1, -1), colors.white),
                    ('TEXTCOLOR', (0, 1), (-1, -1), colors.black),
                    ('ALIGN', (0, 1), (-1, -1), 'LEFT'),
                    ('ALIGN', (2, 1), (2, -1), 'CENTER'),
                    ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
                    ('FONTSIZE', (0, 1), (-1, -1), 8),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
                ]))
                
                elements.append(product_table)
                
                # Add product statistics
                elements.append(Spacer(1, 10))
                total_products = products.count()
                total_stock = sum(p.amountinstock for p in products if p.amountinstock)
                avg_price = sum(float(p.price) for p in products if p.price) / total_products if total_products > 0 else 0
                
                product_stats = f"""
                <b>Product Statistics:</b><br/>
                • Total Products in Menu: {total_products}<br/>
                • Total Items in Stock: {total_stock}<br/>
                • Average Product Price: {avg_price:,.2f} RWF<br/>
                """
                elements.append(Paragraph(product_stats, normal_style))
                
            else:
                elements.append(Paragraph("No products found in menu.", normal_style))
            
            elements.append(Spacer(1, 20))
            
            # ================ SECTION 5: TOP PERFORMING PRODUCTS ================
            if sales.exists() and len(sorted_products) > 0:
                elements.append(Paragraph("5. TOP PERFORMING PRODUCTS", section_style))
                
                # Get top 5 products
                top_products = sorted_products[:5]
                
                top_data = [['Rank', 'Product', 'Sales (RWF)', 'Quantity']]
                
                for idx, (product_name, data) in enumerate(top_products, 1):
                    top_data.append([
                        str(idx),
                        product_name[:20] if product_name else 'N/A',
                        f"{float(data['amount']):,.2f}",
                        str(data['quantity'])
                    ])
                
                top_table = Table(top_data, colWidths=[0.5*inch, 2.5*inch, 1.5*inch, 1*inch])
                top_table.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#E74C3C')),  # Red header
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, 0), 'CENTER'),
                    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 10),
                    ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
                    ('GRID', (0, 0), (-1, -1), 1, colors.black),
                ]))
                
                # Add gold, silver, bronze colors for top 3
                for i in range(1, len(top_data)):
                    if i == 1:
                        top_table.setStyle(TableStyle([
                            ('BACKGROUND', (0, i), (-1, i), colors.HexColor('#FFD700')),  # Gold
                        ]))
                    elif i == 2:
                        top_table.setStyle(TableStyle([
                            ('BACKGROUND', (0, i), (-1, i), colors.HexColor('#C0C0C0')),  # Silver
                        ]))
                    elif i == 3:
                        top_table.setStyle(TableStyle([
                            ('BACKGROUND', (0, i), (-1, i), colors.HexColor('#CD7F32')),  # Bronze
                        ]))
                    else:
                        top_table.setStyle(TableStyle([
                            ('BACKGROUND', (0, i), (-1, i), colors.white),
                        ]))
                    
                    # Set alignment
                    top_table.setStyle(TableStyle([
                        ('ALIGN', (0, i), (0, i), 'CENTER'),
                        ('ALIGN', (2, i), (2, i), 'RIGHT'),
                        ('ALIGN', (3, i), (3, i), 'CENTER'),
                        ('FONTSIZE', (0, i), (-1, i), 9),
                        ('PADDING', (0, i), (-1, i), (6, 4)),
                    ]))
                
                elements.append(top_table)
                elements.append(Spacer(1, 20))
            
            # ================ FOOTER ================
            footer_text = f"""
            <b>Report Generated:</b> {datetime.now().strftime('%d %B %Y %H:%M:%S')}<br/>
            <b>For Internal Use Only</b><br/>
            <i>This report provides a summary of {merchant.username}'s business performance.</i>
            """
            elements.append(Paragraph(footer_text, ParagraphStyle(
                'Footer',
                parent=styles['Normal'],
                fontSize=8,
                alignment=TA_CENTER,
                textColor=colors.grey
            )))
            
            # Build PDF
            doc.build(elements)
            
            # Get PDF value from buffer
            pdf = buffer.getvalue()
            buffer.close()
            
            response.write(pdf)
            print(f"✅ Report generated successfully: {filename}")
            return response
            
        except Exception as e:
            buffer.close()
            print(f"🔥 Error building PDF: {str(e)}")
            import traceback
            traceback.print_exc()
            return Response({"error": f"Error building PDF: {str(e)}"}, status=500)
            
    except Exception as e:
        print(f"🔥 Error in generate_merchant_report: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({"error": str(e)}, status=500)

from django.db.models import Q
from decimal import Decimal
import os
from datetime import datetime
from io import BytesIO
from reportlab.lib.pagesizes import A4, letter, inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, Image, HRFlowable
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT, TA_JUSTIFY
from reportlab.lib import colors
from django.http import HttpResponse
from reportlab.pdfgen import canvas
from reportlab.lib.units import cm
from django.conf import settings

@api_view(['GET'])
def generate_transaction_receipt(request):
    """
    Generate PDF receipt for a transaction
    """
    try:
        transaction_id = request.GET.get('transaction_id')
        
        if not transaction_id:
            return Response({"error": "Transaction ID is required"}, status=400)
        
        # Get transaction details
        try:
            transaction = Transaction.objects.get(transactionid=int(transaction_id))
            print(f"✅ Found transaction: {transaction.transactionid}")
        except Transaction.DoesNotExist:
            print(f"❌ Transaction not found: {transaction_id}")
            return Response({"error": "Transaction not found"}, status=404)
        except ValueError:
            print(f"❌ Invalid transaction ID format: {transaction_id}")
            return Response({"error": "Invalid transaction ID format"}, status=400)
        
        # Get sender details
        try:
            if transaction.sender_type == 'user':
                sender = User.objects.get(userid=transaction.senderid)
                sender_name = sender.username
                sender_email = sender.email
                sender_phone = sender.phonenumber
            else:
                sender = Merchant.objects.get(merchantid=transaction.senderid)
                sender_name = sender.username
                sender_email = sender.email
                sender_phone = sender.phonenumber
        except (User.DoesNotExist, Merchant.DoesNotExist):
            sender_name = "Unknown"
            sender_email = "N/A"
            sender_phone = "N/A"
        
        # Get receiver details
        try:
            if transaction.receiver_type == 'user':
                receiver = User.objects.get(userid=transaction.receiverid)
                receiver_name = receiver.username
                receiver_email = receiver.email
                receiver_phone = receiver.phonenumber
            else:
                receiver = Merchant.objects.get(merchantid=transaction.receiverid)
                receiver_name = receiver.username
                receiver_email = receiver.email
                receiver_phone = receiver.phonenumber
        except (User.DoesNotExist, Merchant.DoesNotExist):
            receiver_name = "Unknown"
            receiver_email = "N/A"
            receiver_phone = "N/A"
        
        # Create response with PDF
        response = HttpResponse(content_type='application/pdf')
        filename = f"transaction_receipt_{transaction.transactionid}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
        response['Content-Disposition'] = f'attachment; filename="{filename}"'
        
        # Create PDF buffer
        buffer = BytesIO()
        
        try:
            # Create the PDF document - using letter size for better receipt format
            doc = SimpleDocTemplate(buffer, pagesize=letter, 
                                   rightMargin=36, leftMargin=36,
                                   topMargin=36, bottomMargin=36)
            
            # Container for the 'Flowable' objects
            elements = []
            
            # Get styles
            styles = getSampleStyleSheet()
            
            # Custom styles
            company_style = ParagraphStyle(
                'CompanyTitle',
                parent=styles['Heading1'],
                fontSize=24,
                spaceAfter=12,
                alignment=TA_CENTER,
                textColor=colors.HexColor('#FF8A00'),
                fontName='Helvetica-Bold'
            )
            
            receipt_title_style = ParagraphStyle(
                'ReceiptTitle',
                parent=styles['Heading2'],
                fontSize=20,
                spaceAfter=6,
                alignment=TA_CENTER,
                textColor=colors.black,
                fontName='Helvetica-Bold'
            )
            
            header_style = ParagraphStyle(
                'Header',
                parent=styles['Heading3'],
                fontSize=11,
                spaceAfter=3,
                alignment=TA_LEFT,
                textColor=colors.grey,
                fontName='Helvetica'
            )
            
            normal_style = ParagraphStyle(
                'Normal',
                parent=styles['Normal'],
                fontSize=10,
                alignment=TA_LEFT,
                textColor=colors.black
            )
            
            bold_style = ParagraphStyle(
                'Bold',
                parent=styles['Normal'],
                fontSize=10,
                alignment=TA_LEFT,
                textColor=colors.black,
                fontName='Helvetica-Bold'
            )
            
            amount_style = ParagraphStyle(
                'Amount',
                parent=styles['Normal'],
                fontSize=14,
                alignment=TA_RIGHT,
                textColor=colors.black,
                fontName='Helvetica-Bold'
            )
            
            footer_style = ParagraphStyle(
                'Footer',
                parent=styles['Normal'],
                fontSize=8,
                alignment=TA_CENTER,
                textColor=colors.grey
            )
            
            # ================ HEADER SECTION ================
            # Company name and receipt title in one row
            header_data = [
                [Paragraph("Company Name", company_style), 
                 Paragraph("RECEIPT", receipt_title_style)]
            ]
            
            header_table = Table(header_data, colWidths=[3*inch, 3*inch])
            header_table.setStyle(TableStyle([
                ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                ('ALIGN', (0, 0), (0, 0), 'LEFT'),
                ('ALIGN', (1, 0), (1, 0), 'RIGHT'),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 10),
            ]))
            
            elements.append(header_table)
            
            # Invoice and date in compact row
            invoice_data = [
                [Paragraph(f"<b>INVOICE #</b> {transaction.transactionid:08d}", header_style),
                 Paragraph(f"<b>DATE</b> {transaction.date.strftime('%m/%d/%Y')}", header_style)]
            ]
            
            invoice_table = Table(invoice_data, colWidths=[3*inch, 3*inch])
            invoice_table.setStyle(TableStyle([
                ('ALIGN', (0, 0), (0, 0), 'LEFT'),
                ('ALIGN', (1, 0), (1, 0), 'RIGHT'),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 10),
            ]))
            
            elements.append(invoice_table)
            
            # Divider line
            elements.append(HRFlowable(width="100%", thickness=1, color=colors.grey))
            elements.append(Spacer(1, 15))
            
            # ================ BILL TO / FROM SECTION ================
            # Create a table with 2 columns for BILL TO and FROM
            billing_data = [
                ['BILL FROM', 'BILL TO'],
                [sender_name, receiver_name],
                [sender_email, receiver_email],
                [sender_phone, receiver_phone],
                [f"{transaction.sender_type.capitalize()} Account", 
                 f"{transaction.receiver_type.capitalize()} Account"],
            ]
            
            billing_table = Table(billing_data, colWidths=[3*inch, 3*inch])
            billing_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (1, 0), colors.HexColor('#FF8A00')),
                ('TEXTCOLOR', (0, 0), (1, 0), colors.white),
                ('FONTNAME', (0, 0), (1, 0), 'Helvetica-Bold'),
                ('ALIGN', (0, 0), (1, 0), 'CENTER'),
                ('FONTSIZE', (0, 0), (1, 0), 11),
                ('BOTTOMPADDING', (0, 0), (1, 0), 8),
                ('BACKGROUND', (0, 1), (1, -1), colors.white),
                ('TEXTCOLOR', (0, 1), (1, -1), colors.black),
                ('FONTNAME', (0, 1), (1, -1), 'Helvetica'),
                ('FONTSIZE', (0, 1), (1, -1), 10),
                ('GRID', (0, 0), (1, -1), 0.5, colors.grey),
                ('PADDING', (0, 0), (1, -1), (6, 4)),
            ]))
            
            elements.append(billing_table)
            elements.append(Spacer(1, 15))
            
            # ================ TRANSACTION DETAILS ================
            elements.append(Paragraph("<b>TRANSACTION DETAILS</b>", bold_style))
            elements.append(Spacer(1, 8))
            
            # Create transaction details table
            transaction_data = [
                ['DESCRIPTION', 'AMOUNT (RWF)'],
                ['Transfer Amount', f"{float(transaction.amount):,.2f}"],
                ['Transaction Fee', f"{float(transaction.charge):,.2f}"],
            ]
            
            transaction_table = Table(transaction_data, colWidths=[4*inch, 2*inch])
            transaction_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (1, 0), colors.HexColor('#F5F5F5')),
                ('TEXTCOLOR', (0, 0), (1, 0), colors.black),
                ('FONTNAME', (0, 0), (1, 0), 'Helvetica-Bold'),
                ('ALIGN', (0, 0), (0, 0), 'LEFT'),
                ('ALIGN', (1, 0), (1, 0), 'RIGHT'),
                ('FONTSIZE', (0, 0), (1, 0), 10),
                ('BOTTOMPADDING', (0, 0), (1, 0), 6),
                ('BACKGROUND', (0, 1), (1, -1), colors.white),
                ('TEXTCOLOR', (0, 1), (1, -1), colors.black),
                ('FONTNAME', (0, 1), (1, -1), 'Helvetica'),
                ('FONTSIZE', (0, 1), (1, -1), 10),
                ('ALIGN', (1, 1), (1, -1), 'RIGHT'),
                ('GRID', (0, 0), (1, -1), 0.5, colors.lightgrey),
                ('PADDING', (0, 0), (1, -1), (6, 4)),
            ]))
            
            elements.append(transaction_table)
            elements.append(Spacer(1, 8))
            
            # ================ TOTAL SECTION ================
            total_amount = float(transaction.amount) + float(transaction.charge)
            
            total_data = [
                ['SUB TOTAL', f"${float(transaction.amount):,.2f}"],
                ['FEE', f"{float(transaction.charge):,.2f}"],
                ['TOTAL', f"<b>{total_amount:,.2f}</b>"],
            ]
            
            total_table = Table(total_data, colWidths=[4*inch, 2*inch])
            total_table.setStyle(TableStyle([
                ('BACKGROUND', (0, 2), (1, 2), colors.HexColor('#FF8A00')),
                ('TEXTCOLOR', (0, 2), (1, 2), colors.white),
                ('FONTNAME', (0, 2), (1, 2), 'Helvetica-Bold'),
                ('ALIGN', (0, 2), (0, 2), 'LEFT'),
                ('ALIGN', (1, 2), (1, 2), 'RIGHT'),
                ('FONTSIZE', (0, 2), (1, 2), 12),
                ('BOTTOMPADDING', (0, 2), (1, 2), 8),
                ('BACKGROUND', (0, 0), (1, 1), colors.white),
                ('TEXTCOLOR', (0, 0), (1, 1), colors.black),
                ('FONTNAME', (0, 0), (1, 1), 'Helvetica'),
                ('FONTSIZE', (0, 0), (1, 1), 10),
                ('ALIGN', (1, 0), (1, 1), 'RIGHT'),
                ('GRID', (0, 0), (1, 2), 0.5, colors.lightgrey),
                ('PADDING', (0, 0), (1, 2), (6, 4)),
            ]))
            
            elements.append(total_table)
            elements.append(Spacer(1, 15))
            
            # ================ PAYMENT TERMS ================
            payment_terms = [
                "1. Total payment due immediately",
                "2. Payment received via electronic transfer",
                f"3. Transaction ID: {transaction.transactionid}",
                f"4. Date: {transaction.date.strftime('%B %d, %Y %H:%M:%S')}",
                "5. Status: Completed Successfully"
            ]
            
            for term in payment_terms:
                elements.append(Paragraph(f"• {term}", normal_style))
                elements.append(Spacer(1, 3))
            
            elements.append(Spacer(1, 15))
            
            # ================ THANK YOU MESSAGE ================
            elements.append(Paragraph(
                "<b>Thank You For Your Business!</b>", 
                ParagraphStyle(
                    'ThankYou',
                    parent=styles['Normal'],
                    fontSize=12,
                    alignment=TA_CENTER,
                    textColor=colors.HexColor('#FF8A00'),
                    fontName='Helvetica-Bold',
                    spaceBefore=20,
                    spaceAfter=10
                )
            ))
            
            elements.append(Paragraph(
                "Make all checks payable to Company Name", 
                ParagraphStyle(
                    'FooterNote',
                    parent=styles['Normal'],
                    fontSize=9,
                    alignment=TA_CENTER,
                    textColor=colors.grey,
                    fontName='Helvetica'
                )
            ))
            
            # ================ FOOTER ================
            elements.append(Spacer(1, 20))
            elements.append(HRFlowable(width="100%", thickness=0.5, color=colors.grey))
            
            footer_text = f"""
            <b>Receipt Generated:</b> {datetime.now().strftime('%d %B %Y %H:%M:%S')}<br/>
            <b>Transaction Reference:</b> {transaction.transactionid}<br/>
            <i>This is an official receipt for your records.</i>
            """
            
            elements.append(Paragraph(footer_text, footer_style))
            
            # Build PDF
            doc.build(elements)
            
            # Get PDF value from buffer
            pdf = buffer.getvalue()
            buffer.close()
            
            response.write(pdf)
            print(f"✅ Receipt generated successfully: {filename}")
            return response
            
        except Exception as e:
            buffer.close()
            print(f"🔥 Error building PDF receipt: {str(e)}")
            import traceback
            traceback.print_exc()
            return Response({"error": f"Error building PDF: {str(e)}"}, status=500)
            
    except Exception as e:
        print(f"🔥 Error in generate_transaction_receipt: {str(e)}")
        import traceback
        traceback.print_exc()
        return Response({"error": str(e)}, status=500)