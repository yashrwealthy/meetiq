import os
import requests
import sys
import re
import time

def upload_chunks(directory, client_id, meeting_id):
    # API endpoint
    url = "http://127.0.0.1:8004/meetings/upload_chunk"
    
    if not os.path.exists(directory):
        print(f"Error: Directory '{directory}' not found.")
        return

    files = [f for f in os.listdir(directory) if f.endswith('.aac')]
    def extract_number(filename):
        # Look for the last number in the filename
        nums = re.findall(r'\d+', filename)
        if nums:
            return int(nums[-1])
        return 0

    files.sort(key=extract_number)
    
    total_chunks = len(files)
    print(f"Found {total_chunks} files to upload in {directory}")
    
    if total_chunks == 0:
        print("No .aac files found.")
        return

    for i, filename in enumerate(files):
        file_path = os.path.join(directory, filename)
        chunk_id = i 
        
        print(f"Uploading {filename} as chunk {chunk_id}/{total_chunks-1}...")
        
        with open(file_path, 'rb') as f:
            files_data = {'file': f}
            data = {
                'client_id': client_id,
                'meeting_id': meeting_id,
                'chunk_id': str(chunk_id),
                'total_chunks': str(total_chunks)
            }
            
            try:
                response = requests.post(url, files=files_data, data=data)
                if response.status_code == 200:
                    print(f"Success: {response.json()}")
                else:
                    print(f"Failed ({response.status_code}): {response.text}")
            except Exception as e:
                print(f"Error uploading {filename}: {str(e)}")
        
        time.sleep(0.1)

if __name__ == "__main__":
    default_folder = "/Users/yashrastogi/Downloads/documents (1)"
    client_id = "123"
    meeting_id = "130"
    
    folder_path = default_folder
    
    if len(sys.argv) > 1:
        folder_path = sys.argv[1]
    
    print(f"Starting upload for Client: {client_id}, Meeting: {meeting_id}")
    upload_chunks(folder_path, client_id, meeting_id)
