import redis
import os
from settings import Settings

def clear_queues():
    settings = Settings()
    print(f"Connecting to Redis at {settings.redis_host}:{settings.redis_port}")
    
    r = redis.Redis(
        host=settings.redis_host,
        port=settings.redis_port,
        db=settings.redis_db,
        password=settings.redis_password,
        decode_responses=True
    )

    # Find all arq queues
    queues = r.keys('arq:queue*')
    print(f"Found queues: {queues}")

    if queues:
        # Delete the queues
        r.delete(*queues)
        print("Deleted all queues.")
    else:
        print("No queues found.")

    # Also check for ZSETS which arq uses for delayed jobs if any?
    # arq uses zset for delayed jobs, usually same name?
    # Actually arq uses a list for the queue and a zset for scheduled/retry jobs.
    # The default queue is a list.
    
    # Check for zsets (scheduled jobs) which might be just 'arq:queue' or 'arq:queue:v2' but usage depends.
    # Standard arq uses the same name for the list, but maybe 'arq:queue:v2' is the list.
    
    # If using ARQ, let's look for known arq patterns.
    # arq uses the queue key as a list.
    
if __name__ == "__main__":
    clear_queues()
