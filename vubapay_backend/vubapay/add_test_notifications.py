import os
import django
import datetime

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'your_project.settings')
django.setup()

from your_app.models import Notification

# Clear existing notifications
Notification.objects.all().delete()

# Add sample notifications
notifications = [
    {
        'title': 'Wrong payment detected',
        'content': 'A wrong payment made by customer for amount 5,000 FRW, you\'re requested to reverse kindly!',
        'urgency': 'high',
        'designated_to': 'user'
    },
    {
        'title': 'Update available',
        'content': 'We got you covered! New updates available in app — pay easily.',
        'urgency': 'medium',
        'designated_to': 'all'
    },
    {
        'title': 'Welcome Bonus',
        'content': 'Congratulations! You received a 1,000 FRW welcome bonus for your first transaction.',
        'urgency': 'low',
        'designated_to': 'user'
    },
    {
        'title': 'Security Alert',
        'content': 'We detected unusual login activity. Please review your account security.',
        'urgency': 'high',
        'designated_to': 'user'
    },
    {
        'title': 'New Feature',
        'content': 'Try our new instant transfer feature. Send money to any bank in seconds!',
        'urgency': 'medium',
        'designated_to': 'all'
    },
]

for i, notif_data in enumerate(notifications):
    # Set different dates for variety
    hours_ago = i * 2  # 0, 2, 4, 6, 8 hours ago
    date = datetime.datetime.now() - datetime.timedelta(hours=hours_ago)
    
    Notification.objects.create(
        title=notif_data['title'],
        content=notif_data['content'],
        urgency=notif_data['urgency'],
        designated_to=notif_data['designated_to'],
        date=date
    )

print(f'Created {len(notifications)} notifications successfully!')