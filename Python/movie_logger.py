"""
================================================================================
MODULE: Focus Destroyer - Movie Logging Engine
DATABASE: PostgreSQL (focus_destroyer)
SCHEMA: the_receipts_sandbox
AUTHOR: eagercricket
================================================================================

I built this engine to be the final word on my movie tracking. It's designed 
to bridge the gap between my local PostgreSQL sandbox and the massive TMDB 
cloud, ensuring that every entry I log is backed by clean, verified metadata. 

WHAT I'VE IMPROVED (The "Quality of Life" Updates):

1. INTELLIGENT DATE SELECTION:
   I hate typing dates. This logic defaults to 'Today', but I can use '-1' for 
   yesterday or '-n' for a few days ago. It handles the timedelta math so I 
   don't have to check a calendar.

2. SEARCH VS. SNIPER MODE:
   I added a dual-track entry system. If I type a title, it pulls a list of 
   the top 5 matches so I can pick the right one (crucial for remakes). 
   If I'm feeling precise, I can just paste a TMDB ID to bypass the search 
   entirely and "snipe" the exact movie I want.

3. DYNAMIC METADATA HARVESTING:
   Once the movie is confirmed, I pull the deep cuts: Country codes, 
   genre arrays, and runtimes.

4. THE "SMART" REWATCH GUARD:
   The script is now self-aware. It pings the 'movies' table for the TMDB ID. 
   If I've seen it before, it auto-flags the rewatch—saving me a keystroke 
   and keeping my data honest.

5. CLEAN DATA COMMIT:
   I'm using parameterized SQL to keep things safe. If the API fails or 
   the DB connection drops, it rolls back the transaction so I never 
   end up with half-baked data in my box.

USAGE:
   Fire it up, follow the prompts, and let the ID Sniper do the heavy 
   lifting if the search results get crowded.
================================================================================
"""

# --- IMPORTS ---
import requests
import psycopg2
from datetime import datetime, timedelta
import sys
from dotenv import load_dotenv
import os

# --- ENVIRONMENT SETUP ---
load_dotenv()

# --- CONFIGURATION ---
TMDB_API_KEY = os.getenv("TMDB_API_KEY")
DB_SCHEMA = os.getenv("DB_SCHEMA")
DB_PARAMS = {
    "dbname": os.getenv("DB_NAME"),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASSWORD"),
    "host": os.getenv("DB_HOST"),
    "port": os.getenv("DB_PORT")
}

# --- VALIDATION CHECKS FOR ENVIRONMENT VARIABLES ---
if not TMDB_API_KEY:
    print("Error: TMDB_API_KEY not found. Check your .env file.")
    sys.exit(1)

if not all(DB_PARAMS.values()):
    missing = [k for k, v in DB_PARAMS.items() if not v]
    print(f"Error: Missing database parameters in .env: {missing}")
    sys.exit(1)

# --- FUNCTION DEFINITIONS ---
def log_movie():
    # --- STEP 0: DATE SELECTION ---
    print(f"\nDate Watched (Enter for Today, '-1' for Yesterday, or YYYY-MM-DD): ", end='', flush=True)
    date_input = input().strip()

    if not date_input:
        final_date = datetime.now().date() 
    elif date_input == "-1":
        final_date = (datetime.now() - timedelta(days=1)).date()
    elif date_input.startswith("-") and date_input[1:].isdigit():
        final_date = (datetime.now() - timedelta(days=abs(int(date_input)))).date()
    else:
        try:
            final_date = datetime.strptime(date_input, "%Y-%m-%d").date()
        except ValueError:
            print("Invalid date format. Defaulting to Today.")
            final_date = datetime.now().date()

    # --- STEP 1: SEARCH (TITLE OR ID) ---
    print("\nStep 1: Enter Movie Title or TMDB ID: ", end='', flush=True)
    query = input().strip()
    
    if query.isdigit():
        tmdb_id = int(query)
    else:
        print("Step 2: Enter Year Released (optional, Enter to skip): ", end='', flush=True)
        year_search = input().strip()
        
        search_url = "https://api.themoviedb.org/3/search/movie"
        params = {"api_key": TMDB_API_KEY, "query": query, "language": "en-US"}
        
        if year_search.isdigit():
            params["primary_release_year"] = int(year_search)
            
        res = requests.get(search_url, params=params).json()
        results = res.get('results', [])
        
        if not results:
            print("Error: Movie not found on TMDB.")
            return

        print("\nI found multiple matches. Which one is correct?")
        display_count = min(len(results), 10)  # Show up to 10 results
        for i in range(display_count):
            r = results[i]
            print(f"[{i}] {r.get('title')} ({r.get('release_date', '????')[:4]}) - ID: {r.get('id')}")

        choice = input(f"\nEnter number (0-{display_count-1}, default 0): ").strip()
        idx = int(choice) if (choice and choice.isdigit() and int(choice) < display_count) else 0
        tmdb_id = results[idx]['id']

    # --- STEP 2: FETCH DEEP METADATA ---
    detail_params = {"api_key": TMDB_API_KEY, "language": "en-US"}
    d = requests.get(f"https://api.themoviedb.org/3/movie/{tmdb_id}", params=detail_params, timeout=10).json()

    official_title = d.get('title') # Get the official title from TMDB
    year_released = d.get('release_date', '0000')[:4] # Extract year from release date
    country = d.get('production_countries', [{}])[0].get('iso_3166_1', '??') # Get country code or default you want
    genres_list = [g.get('name') for g in d.get('genres', [])] # Extract genre names into a list
    runtime = d.get('runtime', 0) # Runtime in minutes, default to 0 if not available

    # --- STEP 3: STATUS & RATING ---
    print(f"\n--- Logging: {official_title} ({year_released}) ---")
    print(f"Watched on: {final_date}")
    print("1. Finished\t2. Skimmed\t3. Dropped")
    choice = input("Select (default 1): ") or "1"
    status_map = {"1": "Finished", "2": "Skimmed", "3": "Dropped"}
    comp_status = status_map.get(choice, "Finished")

    rating = None # Only ask for rating if not dropped
    if comp_status != "Dropped":
        rating_input = input(f"Rating (1-10): ").strip()
        rating = float(rating_input) if rating_input else None # Allow empty rating
    
    review = input("Review/Notes: ")

    # --- STEP 4: DB OPERATIONS (LATE-OPEN) ---
    try:
        conn = psycopg2.connect(**DB_PARAMS)
        cur = conn.cursor()

        # Auto-Rewatch detection via TMDB ID
        cur.execute(f"SELECT 1 FROM {DB_SCHEMA}.movies WHERE tmdb_id = %s LIMIT 1", (tmdb_id,))
        is_rewatch = cur.fetchone() is not None
        # Auto-flag as rewatch if TMDB ID exists in DB
        if is_rewatch:
            print("[AUTO-FLAG] Database confirms this is a REWATCH.") 
        else:
            user_choice = input("Is this a rewatch? (y/n, default n): ").lower().strip()
            is_rewatch = (user_choice == 'y')

        # DB COMMIT
        query = f"""
            INSERT INTO {DB_SCHEMA}.movies (
                movie_title, date_watched, year_released, country, 
                genre, runtime, rating, review, is_rewatch, 
                completion_status, tmdb_id
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """
        cur.execute(query, (
            official_title, final_date, year_released, country, 
            genres_list, runtime, rating, review, is_rewatch, 
            comp_status, tmdb_id
        ))
        conn.commit()
        print(f"\nSUCCESS: '{official_title}' logged for {final_date}.")

    except Exception as e:
        if 'conn' in locals(): conn.rollback()
        print(f"DATABASE ERROR: {e}")
    finally:
        if 'cur' in locals(): cur.close()
        if 'conn' in locals(): conn.close()

if __name__ == "__main__":
    log_movie()