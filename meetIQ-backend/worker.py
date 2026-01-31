import json
import os
import tempfile
from pathlib import Path
from typing import Any, Dict
from datetime import datetime

from arq.connections import RedisSettings

from settings import Settings
from v2.agents.meeting_agent import MeetingAgent
from v2.agents.memory_agent import MemoryAgent
from v2.services.storage import StorageService
from v2.models.schemas import MeetingEvent, MeetingInsight, ClientMemory
from services.stt_service import transcribe_audio

# Load settings
try:
    settings = Settings()
except Exception:
    # Fallback if .env not loaded or settings failed
    class MockSettings:
        gemini_api_key = os.getenv("GEMINI_API_KEY", "")
    settings = MockSettings()

# Use port 6379 for v2 worker to match API
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")

# --- V2 Tasks ---

async def dispatch_processing_task_v2(ctx: Dict[str, Any], client_id: str, meeting_id: str, total_chunks: int) -> Dict[str, Any]:
    storage = StorageService()
    try:
        print(f"[v2] Dispatching processing for meeting {meeting_id} with {total_chunks} chunks")
        redis = ctx['redis']
        base_dir = Path("uploads") / client_id / meeting_id
        
        # Reset the processed counter to 0 to ensure accurate tracking for this run
        processed_key = f"v2:meeting:{client_id}:{meeting_id}:processed"
        await redis.set(processed_key, 0)
        
        for i in range(total_chunks):
            # Check for multiple audio formats since Gemini supports webm, mp3, aac, wav, etc.
            if storage.use_s3:
                # Try to find the chunk with any supported extension
                possible_extensions = ['.webm', '.aac', '.mp3', '.wav']
                file_path = None
                
                for ext in possible_extensions:
                    potential_key = f"uploads/{client_id}/{meeting_id}/chunk_{i}{ext}"
                    try:
                        storage.s3_client.head_object(Bucket=storage.bucket_name, Key=potential_key)
                        file_path = f"s3://{storage.bucket_name}/{potential_key}"
                        break
                    except:
                        continue
                
                if not file_path:
                    # Default to .webm if nothing found
                    file_path = f"s3://{storage.bucket_name}/uploads/{client_id}/{meeting_id}/chunk_{i}.webm"
            else:
                # Local storage - check what file exists
                possible_files = [
                    base_dir / f"chunk_{i}.webm",
                    base_dir / f"chunk_{i}.aac",
                    base_dir / f"chunk_{i}.mp3",
                    base_dir / f"chunk_{i}.wav"
                ]
                
                file_path = None
                for pf in possible_files:
                    if pf.exists():
                        file_path = str(pf)
                        break
                
                if not file_path:
                    # Default to .webm
                    file_path = str(base_dir / f"chunk_{i}.webm")

            await redis.enqueue_job(
                'transcribe_chunk_task_v2',
                file_path,
                client_id,
                meeting_id,
                i,
                total_chunks,
                _queue_name='arq:queue:v2'
            )
        
        return {"status": "dispatched", "chunks": total_chunks}
    except Exception as e:
        print(f"[v2] Error dispatching tasks for {meeting_id}: {e}")
        raise e

async def transcribe_chunk_task_v2(ctx: Dict[str, Any], file_path: str, client_id: str, meeting_id: str, chunk_id: int, total_chunks: int) -> Dict[str, Any]:
    # Try to import transcribe_audio_gemini, fallback to transcribe_audio
    try:
        from services.gemini_stt_service import transcribe_audio_gemini as transcribe_func
    except (ImportError, AttributeError):
        print("[v2] transcribe_audio_gemini not available, using fallback transcribe_audio")
        from services.gemini_stt_service import transcribe_audio as transcribe_func
    
    storage = StorageService()
    temp_file_path = None
    
    try:
        if file_path.startswith("s3://"):
            # Format: s3://bucket/key
            bucket = file_path.split("/")[2]
            key = "/".join(file_path.split("/")[3:])
            
            suffix = Path(key).suffix
            tf = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
            temp_file_path = tf.name
            tf.close()
            
            print(f"[v2] Downloading S3 chunk to {temp_file_path}")
            storage.download_file(key, temp_file_path)
            local_input_path = temp_file_path
        else:
            local_input_path = file_path

        transcript_json = await transcribe_func(local_input_path) or ""
        
        if storage.use_s3:
            json_key = f"uploads/{client_id}/{meeting_id}/chunk_{chunk_id}.json"
            storage.s3_client.put_object(
                Bucket=storage.bucket_name,
                Key=json_key,
                Body=transcript_json.encode("utf-8")
            )
        else:
            json_path = Path(local_input_path).parent / f"chunk_{chunk_id}.json"
            json_path.parent.mkdir(parents=True, exist_ok=True)
            with open(json_path, 'w') as f:
                f.write(transcript_json)
            
        redis = ctx['redis']
        key = f"v2:meeting:{client_id}:{meeting_id}:processed"
        count = await redis.incr(key)
        
        print(f"[v2] Processed chunk {chunk_id} for meeting {meeting_id}. Total: {count}/{total_chunks}")
    
        if int(count) == int(total_chunks):
            print(f"[v2] All chunks processed for {meeting_id}. Enqueuing merge task.")
            merge_job_id = f"v2-merge-{client_id}-{meeting_id}"
            await redis.enqueue_job(
                'merge_and_summarize_task_v2', 
                client_id, 
                meeting_id, 
                total_chunks,
                _job_id=merge_job_id,
                _queue_name='arq:queue:v2'
            )
            
        return {"chunk_id": chunk_id, "status": "processed"}
    except Exception as e:
        print(f"[v2] Error transcribing chunk {chunk_id}: {e}")
        raise e
    finally:
        if temp_file_path and os.path.exists(temp_file_path):
            os.remove(temp_file_path)

async def merge_and_summarize_task_v2(ctx: Dict[str, Any], client_id: str, meeting_id: str, total_chunks: int) -> Dict[str, Any]:
    base_dir = Path("uploads") / client_id / meeting_id
    storage = StorageService()
    
    try:
        print(f"[v2] Merging {total_chunks} chunks for meeting {meeting_id} (3-Layer Pipeline)")
        all_segments = []
        audio_chunks_ref = []
        
        for i in range(total_chunks):
            if storage.use_s3:
                json_key = f"uploads/{client_id}/{meeting_id}/chunk_{i}.json"
                try:
                    resp = storage.s3_client.get_object(Bucket=storage.bucket_name, Key=json_key)
                    content = resp['Body'].read().decode('utf-8')
                    chunk_data = json.loads(content)
                    
                    if "segments" in chunk_data:
                        all_segments.extend(chunk_data["segments"])
                    
                except Exception as e:
                    print(f"Failed to read transcript chunk {i} from S3: {e}")
                
                audio_chunks_ref.append(f"s3://{storage.bucket_name}/uploads/{client_id}/{meeting_id}/chunk_{i}.aac")
            else:
                json_path = base_dir / f"chunk_{i}.json"
                if json_path.exists():
                    with open(json_path, 'r') as f:
                        chunk_data = json.loads(f.read())
                        
                        if "segments" in chunk_data:
                            all_segments.extend(chunk_data["segments"])
                
                audio_chunks_ref.append(f"chunk_{i}.aac")
        
        merged_text = "\n".join([
            f"[{seg.get('timestamp', '')}] {seg.get('speaker', 'Unknown')}: {seg.get('content', '')}"
            for seg in all_segments
        ])
        
        event = MeetingEvent(
            meeting_id=meeting_id,
            client_id=client_id,
            timestamp=datetime.now(),
            audio_chunks_ref=audio_chunks_ref,
            transcript=merged_text,
            speaker_map={} 
        )
        storage.save_raw_event(event)
        
        meeting_agent = MeetingAgent(api_key=settings.gemini_api_key)
        insight = await meeting_agent.analyze(merged_text, meeting_id)
        storage.save_meeting_insight(client_id, insight)
        
        current_memory = storage.load_client_memory(client_id)
        
        memory_agent = MemoryAgent(api_key=settings.gemini_api_key)
        updated_memory = await memory_agent.update_memory(current_memory, insight)
        
        updated_memory.last_updated_from_meeting_id = meeting_id
        
        storage.save_client_memory(updated_memory)
        redis = ctx["redis"]
        result_key = f"v2:meeting:{client_id}:{meeting_id}:result"
        await redis.set(result_key, insight.model_dump_json())
        segments_key = f"v2:meeting:{client_id}:{meeting_id}:segments"
        await redis.set(segments_key, json.dumps(all_segments))
        
        print(f"[v2] Pipeline Complete: Event Saved -> Insight Generated -> Memory Updated ({client_id})")
        print(f"[v2] Total segments processed: {len(all_segments)}")
        return insight.model_dump()
        
    except Exception as e:
        print(f"[v2] Error applying meeting intelligence/memory: {e}")
        # Store error in Redis for status endpoint
        try:
            redis = ctx["redis"]
            error_key = f"v2:meeting:{client_id}:{meeting_id}:error"
            await redis.set(error_key, str(e))
        except Exception as redis_err:
            print(f"[v2] Failed to store error in Redis: {redis_err}")
        raise e

def create_redis_settings() -> RedisSettings:
    """Helper to create RedisSettings with correct parameters."""
    settings = RedisSettings.from_dsn(REDIS_URL.replace("localhost", "127.0.0.1"))
    settings.conn_timeout = 10
    settings.conn_retries = 5
    settings.conn_retry_delay = 1
    return settings

class WorkerSettings:
    functions = [dispatch_processing_task_v2, transcribe_chunk_task_v2, merge_and_summarize_task_v2]
    
    redis_settings = create_redis_settings()
    queue_name = 'arq:queue:v2'

