# --- IMPORTS ---
import requests
import psycopg2
from datetime import datetime, timedelta
import sys
from dotenv import load_dotenv
import os

load_dotenv()

TMDB_API_KEY = os.getenv("TMDB_API_KEY")
DB_SCHEMA = os.getenv("DB_SCHEMA")
DB_PARAMS = {
    "dbname": os.getenv("DB_NAME"),
    "user": os.getenv("DB_USER"),
    "password": os.getenv("DB_PASSWORD"),
    "host": os.getenv("DB_HOST"),
    "port": os.getenv("DB_PORT")
}

if not TMDB_API_KEY:
    print("Error: TMDB_API_KEY not found. Check your .env file.")
    sys.exit(1)

if not all(DB_PARAMS.values()):
    missing = [k for k, v in DB_PARAMS.items() if not v]
    print(f"Error: Missing database parameters in .env: {missing}")
    sys.exit(1)

def log_movie():
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

    # --- SEARCH (TITLE OR ID) ---
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
        display_count = min(len(results), 10)
        for i in range(display_count):
            r = results[i]
            print(f"[{i}] {r.get('title')} ({r.get('release_date', '????')[:4]}) - ID: {r.get('id')}")

        choice = input(f"\nEnter number (0-{display_count-1}, default 0): ").strip()
        idx = int(choice) if (choice and choice.isdigit() and int(choice) < display_count) else 0
        tmdb_id = results[idx]['id']

    # --- STEP 2: FETCH DEEP METADATA ---
    detail_params = {"api_key": TMDB_API_KEY, "language": "en-US"}
    d = requests.get(f"https://api.themoviedb.org/3/movie/{tmdb_id}", params=detail_params, timeout=10).json()

    official_title = d.get('title')
    year_released = d.get('release_date', '0000')[:4] 
    country = d.get('production_countries', [{}])[0].get('iso_3166_1', '??') # Get country code or default you want
    genres_list = [g.get('name') for g in d.get('genres', [])] # Extract genre names into a list
    runtime = d.get('runtime', 0)

    # --- STATUS & RATING ---
    print(f"\n--- Logging: {official_title} ({year_released}) ---")
    print(f"Watched on: {final_date}")
    print("1. Finished\t2. Skimmed\t3. Dropped")
    choice = input("Select (default 1): ") or "1"
    status_map = {"1": "Finished", "2": "Skimmed", "3": "Dropped"}
    comp_status = status_map.get(choice, "Finished")

    rating = None 
    if comp_status != "Dropped":
        rating_input = input(f"Rating (1-10): ").strip()
        rating = float(rating_input) if rating_input else None 
    
    review = input("Review/Notes: ")

    # --- DB OPERATIONS ---
    try:
        conn = psycopg2.connect(**DB_PARAMS)
        cur = conn.cursor()

        cur.execute(f"SELECT 1 FROM {DB_SCHEMA}.movies WHERE tmdb_id = %s LIMIT 1", (tmdb_id,))
        is_rewatch = cur.fetchone() is not None
        if is_rewatch:
            print("[AUTO-FLAG] Database confirms this is a REWATCH.") 
        else:
            user_choice = input("Is this a rewatch? (y/n, default n): ").lower().strip()
            is_rewatch = (user_choice == 'y')

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
