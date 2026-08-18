from app import app
import logging

with app.app_context():
    app.logger.error("Test Error: This is a test notification to Discord!")

print("Sent test error.")
