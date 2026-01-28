from django.urls import path
from .views import (
    users, merchants, products, get_user_transactions, register,
    process_payment, login, get_user_notifications, test_notifications,
    get_all_notifications, update_profile, update_profile_picture,
    get_user_details, find_user_by_paycode, merchant_details, create_product, merchant_products, merchant_menu,
    add_to_menu, remove_from_menu, merchant_custom_fields, update_product,
    delete_product, toggle_product_availability, upload_product_image,
    get_categories, test_endpoint, create_order, get_customer_orders,
    get_merchant_orders, get_order_details, update_order_status, get_unpaid_orders,
    cancel_order, mark_order_paid, get_merchant_payment_details, get_merchant_order_notifications, get_payable_orders, generate_merchant_report
)
from django.conf.urls.static import static
from django.conf import settings
from . import views

urlpatterns = [
    # Existing endpoints
    path('users/', users),
    path('merchants/', merchants),
    path('products/', products),
    path('register/', register),
    path("login/", login, name="login"),
    path('notifications/', get_user_notifications, name='get_notifications'),
    path('notifications/test/', test_notifications, name='test_notifications'),
    path('notifications/all/', get_all_notifications, name='get_all_notifications'),
    path('user-details/', get_user_details, name='get_user_details'),
    path('update-profile/', update_profile, name='update_profile'),
    path('update-profile-picture/', update_profile_picture, name='update_profile_picture'),
    path('find-user-by-paycode/', find_user_by_paycode, name='find_user_by_paycode'),
    path('process-payment/', process_payment, name='process_payment'),
    path('get-user-transactions/', get_user_transactions, name='get_user_transactions'),
    
    # NEW: Merchant product management endpoints
    path('merchant-details/', merchant_details, name='merchant_details'),
    path('create-product/', create_product, name='create_product'),
    path('merchant-products/', merchant_products, name='merchant_products'),
    path('merchant-menu/', merchant_menu, name='merchant_menu'),
    path('add-to-menu/', add_to_menu, name='add_to_menu'),
    path('remove-from-menu/', remove_from_menu, name='remove_from_menu'),
    path('merchant-custom-fields/', merchant_custom_fields, name='merchant_custom_fields'),
    path('update-product/', update_product, name='update_product'),
    path('delete-product/', delete_product, name='delete_product'),
    path('toggle-product-availability/', toggle_product_availability, name='toggle_product_availability'),
    path('upload-product-image/', upload_product_image, name='upload_product_image'),
    path('get-categories/', get_categories, name='get_categories'),
    path('test/', test_endpoint, name='test_endpoint'),
    path('create-order/', create_order, name='create_order'),
    path('customer-orders/', get_customer_orders, name='customer_orders'),
    path('merchant-orders/', get_merchant_orders, name='merchant_orders'),
    path('order-details/', get_order_details, name='order_details'),
    path('update-order-status/', update_order_status, name='update_order_status'),
    path('create-order/', views.create_order, name='create_order'),
    path('get-customer-orders/', views.get_customer_orders, name='get_customer_orders'),
    path('get-merchant-orders/', views.get_merchant_orders, name='get_merchant_orders'),
    path('get-unpaid-orders/', get_unpaid_orders, name='get_unpaid_orders'),
    path('cancel-order/', cancel_order, name='cancel_order'),
    path('mark-order-paid/', mark_order_paid, name='mark_order_paid'),
    path('get-order-details/', get_order_details, name='get_order_details'),
    path('merchant-payment-details/', get_merchant_payment_details, name='merchant_payment_details'),
    path('get-merchant-order-notifications/', get_merchant_order_notifications, name='get_merchant_order_notifications'),
    path('get-payable-orders/', get_payable_orders, name='get_payable_orders'),
    path('verify-pin/', views.verify_pin, name='verify_pin'),
    # Admin URLs
    path('admin/', views.admin_dashboard, name='admin_dashboard'),
    path('admin-dashboard/', views.admin_dashboard, name='admin_dashboard'),
    path('search-by-paycode/', views.search_by_paycode, name='search_by_paycode'),
    path('create-entry/', views.create_entry, name='create_entry'),
    path('delete-entry/<str:entry_type>/<int:entry_id>/', views.delete_entry, name='delete_entry'),
    
    # CRUD operations for all models
    path('admin/create-user/', views.create_user_admin, name='admin_create_user'),
    path('admin/create-merchant/', views.create_merchant_admin, name='admin_create_merchant'),
    path('admin/create-product/', views.create_product_admin, name='admin_create_product'),
    path('admin/create-service/', views.create_service_admin, name='admin_create_service'),
    path('generate-merchant-report/', generate_merchant_report, name='generate_merchant_report'),
    path('generate-transaction-receipt/', views.generate_transaction_receipt, name='generate_transaction_receipt'),

] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)