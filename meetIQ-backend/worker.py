import asyncio
import json
import os
import shutil
from pathlib import Path
from typing import Any, Dict

from arq import create_pool
from arq.connections import RedisSettings

from agents.meeting_agent import MeetingAgent
from services.stt_service import transcribe_audio
from utils.cleanup import cleanup_file

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")


async def process_meeting_task(ctx: Dict[str, Any], file_path: str, meeting_id: str) -> Dict[str, Any]:
    try:
        print(f"Starting processing for meeting {meeting_id} with file {file_path}")
        
        transcript = await transcribe_audio(file_path)
        
        if not transcript or not transcript.strip():
            return {
                "is_financial_meeting": False,
                "financial_products": [],
                "client_intent": "",
                "meeting_summary": [],
                "action_items": [],
                "follow_up_date": None,
                "confidence_level": "low",
                "transcript": transcript or "",
            }

        agent = MeetingAgent()
        result = await agent.run(transcript)
    
        result_dict = result.dict()
        result_dict["transcript"] = transcript
        return result_dict
    
    except Exception as e:
        print(f"Error processing meeting {meeting_id}: {e}")
        raise e
    finally:
        cleanup_file(file_path)


async def dispatch_processing_task(ctx: Dict[str, Any], client_id: str, meeting_id: str, total_chunks: int) -> Dict[str, Any]:
    try:
        print(f"Dispatching processing for meeting {meeting_id} with {total_chunks} chunks")
        redis = ctx['redis']
        base_dir = Path("uploads") / client_id / meeting_id
        
        # Reset the processed counter to 0 to ensure accurate tracking for this run
        processed_key = f"meeting:{client_id}:{meeting_id}:processed"
        await redis.set(processed_key, 0)
        
        for i in range(total_chunks):
            file_path = base_dir / f"chunk_{i}.aac"
            await redis.enqueue_job(
                'transcribe_chunk_task',
                str(file_path),
                client_id,
                meeting_id,
                i,
                total_chunks
            )
        
        return {"status": "dispatched", "chunks": total_chunks}
    except Exception as e:
        print(f"Error dispatching tasks for {meeting_id}: {e}")
        raise e


async def transcribe_chunk_task(ctx: Dict[str, Any], file_path: str, client_id: str, meeting_id: str, chunk_id: int, total_chunks: int) -> Dict[str, Any]:
    try:
        transcript = await transcribe_audio(file_path) or ""
        txt_path = Path(file_path).with_suffix('.txt')
        txt_path.parent.mkdir(parents=True, exist_ok=True)
        with open(txt_path, 'w') as f:
            f.write(transcript)
        redis = ctx['redis']
        key = f"meeting:{client_id}:{meeting_id}:processed"
        count = await redis.incr(key)
        
        print(f"Processed chunk {chunk_id} for meeting {meeting_id}. Total: {count}/{total_chunks}")
    
        if int(count) == int(total_chunks):
            print(f"All chunks processed for {meeting_id}. Enqueuing merge task.")
            # Use deterministic job_id so client can poll it
            merge_job_id = f"merge-{client_id}-{meeting_id}"
            await redis.enqueue_job(
                'merge_and_summarize_task', 
                client_id, 
                meeting_id, 
                total_chunks,
                _job_id=merge_job_id
            )
            
        return {"chunk_id": chunk_id, "status": "processed"}
    except Exception as e:
        print(f"Error transcribing chunk {chunk_id}: {e}")
        raise e


async def merge_and_summarize_task(ctx: Dict[str, Any], client_id: str, meeting_id: str, total_chunks: int) -> Dict[str, Any]:
    base_dir = Path("uploads") / client_id / meeting_id
    try:
        print(f"Merging {total_chunks} chunks for meeting {meeting_id}")
        full_transcript = []
        
        # 1. Merge transcripts
        for i in range(total_chunks):
            txt_path = base_dir / f"chunk_{i}.txt"
            if txt_path.exists():
                with open(txt_path, 'r') as f:
                    full_transcript.append(f.read())
            else:
                print(f"Warning: Chunk {i} transcription missing")
        
        merged_text = "\n".join(full_transcript)
        
        # Store the aggregated transcription
        transcript_path = base_dir / "full_transcript.txt"
        with open(transcript_path, 'w') as f:
            f.write(merged_text)
        print(f"Stored full transcript to {transcript_path}")
        
        # 2. Generate Summary
        agent = MeetingAgent()
        result = await agent.run(merged_text)
        
        result_dict = result.dict()
        result_dict["transcript"] = merged_text

        result_path = base_dir / "meeting_summary.json"
        with open(result_path, 'w') as f:
            json.dump(result_dict, f, indent=2)
        print(f"Stored meeting summary to {result_path}")

        redis = ctx["redis"]
        result_key = f"meeting:{client_id}:{meeting_id}:result"
        await redis.set(result_key, json.dumps(result_dict, separators=(",", ":")))
        return result_dict
        
    except Exception as e:
        print(f"Error merging meeting {meeting_id}: {e}")
        raise e
    finally:
        # 3. Cleanup directory
        # if base_dir.exists():
        #    shutil.rmtree(base_dir, ignore_errors=True)
        pass


class WorkerSettings:
    functions = [process_meeting_task, transcribe_chunk_task, merge_and_summarize_task, dispatch_processing_task]
    redis_settings = RedisSettings.from_dsn(REDIS_URL)
    on_startup = None
    on_shutdown = None
