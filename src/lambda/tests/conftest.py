import os
import sys

LAMBDA_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "analyze_vibration"))
if LAMBDA_DIR not in sys.path:
    sys.path.insert(0, LAMBDA_DIR)

os.environ.setdefault("TABLE_NAME", "machine_state")
os.environ.setdefault("AWS_DEFAULT_REGION", "eu-west-3")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")