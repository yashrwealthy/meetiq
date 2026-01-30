import json
import os
import logging
import boto3
from typing import Optional, Any
from botocore.exceptions import ClientError
from ..models.schemas import MeetingEvent, MeetingInsight, ClientMemory
from settings import get_settings


logger = logging.getLogger(__name__)

class StorageService:
    def __init__(self, base_dir: str = "uploads"):
        self.base_dir = base_dir
        try:
            self.settings = get_settings()
            # Basic check if s3 is configured
            if self.settings.bucket_name and self.settings.s3_access_key and self.settings.s3_secret_key:
                self.use_s3 = True
                self.bucket_name = self.settings.bucket_name
                self.s3_client = boto3.client(
                    's3',
                    region_name=self.settings.s3_region,
                    aws_access_key_id=self.settings.s3_access_key,
                    aws_secret_access_key=self.settings.s3_secret_key
                )
            else:
                self.use_s3 = False
        except Exception as e:
            logger.warning(f"Could not load settings or S3 config: {e}")
            self.use_s3 = False

    def _get_client_dir(self, client_id: str) -> str:
        return os.path.join(self.base_dir, str(client_id))

    def _get_meeting_dir(self, client_id: str, meeting_id: str) -> str:
        return os.path.join(self._get_client_dir(client_id), str(meeting_id))

    def _ensure_dir(self, path: str):
        if not self.use_s3:
            os.makedirs(path, exist_ok=True)

    def _s3_upload_json(self, key: str, data: dict):
        try:
            self.s3_client.put_object(
                Bucket=self.bucket_name,
                Key=key,
                Body=json.dumps(data, indent=2),
                ContentType='application/json'
            )
        except ClientError as e:
            logger.error(f"S3 Upload Error: {e}")
            raise e

    def _s3_download_json(self, key: str) -> Optional[dict]:
        try:
            response = self.s3_client.get_object(Bucket=self.bucket_name, Key=key)
            content = response['Body'].read().decode('utf-8')
            return json.loads(content)
        except ClientError as e:
            if e.response['Error']['Code'] == "NoSuchKey":
                return None
            logger.error(f"S3 Download Error: {e}")
            raise e

    def upload_file(self, local_path: str, s3_key: str):
        if self.use_s3:
            self.s3_client.upload_file(local_path, self.bucket_name, s3_key)
            logger.info(f"Uploaded {local_path} to s3://{self.bucket_name}/{s3_key}")
        else:
            pass

    def download_file(self, s3_key: str, local_path: str):
        if self.use_s3:
            # Ensure local dir exists
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            self.s3_client.download_file(self.bucket_name, s3_key, local_path)
        else:
            pass

    # --- Layer 1: Raw Events ---
    def save_raw_event(self, event: MeetingEvent):
        path = self._get_meeting_dir(event.client_id, event.meeting_id)
        if self.use_s3:
            key = f"{path}/raw_event.json"
            # model_dump(mode='json') handles datetime etc
            self._s3_upload_json(key, event.model_dump(mode='json'))
            logger.info(f"Saved Raw Event to S3: {key}")
        else:
            self._ensure_dir(path)
            file_path = os.path.join(path, "raw_event.json")
            with open(file_path, "w") as f:
                f.write(event.model_dump_json(indent=2))
            logger.info(f"Saved Raw Event to {file_path}")

    def save_meeting_insight(self, client_id: str, insight: MeetingInsight):
        path = self._get_meeting_dir(client_id, insight.meeting_id)
        if self.use_s3:
            key = f"{path}/meeting_insight.json"
            self._s3_upload_json(key, insight.model_dump(mode='json'))
            logger.info(f"Saved Meeting Insight to S3: {key}")
        else:
            self._ensure_dir(path)
            file_path = os.path.join(path, "meeting_insight.json")
            with open(file_path, "w") as f:
                f.write(insight.model_dump_json(indent=2))
            logger.info(f"Saved Meeting Insight to {file_path}")

    def load_client_memory(self, client_id: str) -> ClientMemory:
        path = self._get_client_dir(client_id)
        if self.use_s3:
            key = f"{path}/client_memory.json"
            data = self._s3_download_json(key)
            if data:
                return ClientMemory(**data)
        else:
            file_path = os.path.join(path, "client_memory.json")
            if os.path.exists(file_path):
                with open(file_path, "r") as f:
                    try:
                        data = json.load(f)
                        return ClientMemory(**data)
                    except Exception as e:
                        logger.warning(f"Failed to load memory for {client_id}, initializing new: {e}")
        
        return ClientMemory(client_id=client_id)

    def save_client_memory(self, memory: ClientMemory):
        path = self._get_client_dir(memory.client_id)
        if self.use_s3:
            key = f"{path}/client_memory.json"
            self._s3_upload_json(key, memory.model_dump(mode='json'))
            logger.info(f"Updated Client Memory S3: {key}")
        else:
            self._ensure_dir(path)
            file_path = os.path.join(path, "client_memory.json")
            with open(file_path, "w") as f:
                f.write(memory.model_dump_json(indent=2))
            logger.info(f"Updated Client Memory at {file_path}")
