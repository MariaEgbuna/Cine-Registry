# --- IMPORTS ---
import requests
import psycopg2
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

def add_series():
    # --- TITLE OR ID SEARCH ---
    print("\n--- I'm in Series Registry Mode ---")
    query = input("Series Title or TMDB ID (e.g., 4506): ").strip()
    
    if query.isdigit():
        tmdb_id = int(query)
    else:
        year_input = input("Release Year (optional, press Enter to skip): ").strip()
        search_url = "https://api.themoviedb.org/3/search/tv"
        search_params = {"api_key": TMDB_API_KEY, "query": query, "language": "en-US"}
        
        if year_input.isdigit():
            search_params["first_air_date_year"] = int(year_input)
            
        try:
            res = requests.get(search_url, params=search_params, timeout=10).json()
            results = res.get('results', [])
        except Exception as e:
            print(f"API Connection Error: {e}")
            return

        if not results:
            print("Error: I couldn't find that series on TMDB.")
            return

        print("\nI found multiple matches. Which one is correct?")
        display_count = min(len(results), 10)  # Show up to 10 results
        for i in range(display_count):
            r = results[i]
            print(f"[{i}] {r.get('name')} ({r.get('first_air_date', '????')[:4]}) - ID: {r.get('id')}")

        choice = input(f"\nEnter number (0-{display_count-1}, default 0): ").strip()
        idx = int(choice) if (choice and choice.isdigit() and int(choice) < display_count) else 0
        tmdb_id = results[idx]['id']
    
    # --- FETCH METADATA ---
    detail_params = {"api_key": TMDB_API_KEY, "language": "en-US"}
    d = requests.get(f"https://api.themoviedb.org/3/tv/{tmdb_id}", params=detail_params, timeout=10).json()
    
    title = d.get('name')
    year_released = int(d.get('first_air_date', '0000')[:4]) 
    print(f"\nTargeting: {title} ({year_released})") 
    
    confirm = input("Is this the correct show? (y/n): ").strip().lower()
    if confirm != 'y':
        print("Aborting registration.")
        return

    # --- MAPPING DATA ---
    api_countries = d.get('origin_country', []) # list of country codes (e.g., ['US', 'CA'])
    detected_country = api_countries[0] if api_countries else '??'
    
    tmdb_status = d.get('status')
    status_map = {
        "Returning Series": "Returning",
        "Ended": "Ended",
        "Canceled": "Cancelled",
        "In Production": "Returning",
        "Planned": "TBD"
    }
    final_status = status_map.get(tmdb_status, "TBD")

    year_completed = int(d.get('last_air_date')[:4]) if (final_status in ['Ended', 'Cancelled'] and d.get('last_air_date')) else None
    total_seasons = d.get('number_of_seasons', 0)
    total_episodes = d.get('number_of_episodes', 0)

    runtimes = d.get('episode_run_time', [])
    last_ep = d.get('last_episode_to_air', {})
    avg_runtime = int(sum(runtimes) / len(runtimes)) if runtimes else (last_ep.get('runtime') if last_ep and last_ep.get('runtime') else 0)

    genres = [g.get('name') for g in d.get('genres', [])]
    platform = d.get('networks', [{}])[0].get('name', 'Unknown')

    print(f"\nSELECTED: {title} ({year_released})")
    print(f"Stats: {total_seasons} Seasons, {total_episodes} Episodes on {platform}")
    
    user_country = input(f"Confirm country (Enter for '{detected_country}' or type new code): ").strip().upper()
    final_country = user_country if user_country else detected_country

    pre_log_input = input(f"Seasons I watched PRIOR to logging (0-{total_seasons}, default 0): ").strip()
    seasons_pre_log = int(pre_log_input) if (pre_log_input and pre_log_input.isdigit()) else 0

    # --- DB CONNECTION AND COMMIT ---
    try:
        conn = psycopg2.connect(**DB_PARAMS)
        cur = conn.cursor()

        cur.execute(f"SELECT title FROM {DB_SCHEMA}.series_metadata WHERE tmdb_id = %s", (tmdb_id,))
        if cur.fetchone():
            print(f"\n[!] ALERT: This show is already in the database.")
            return

        # Commit Data using Stored Procedure
        cur.execute(f"""
            CALL {DB_SCHEMA}.add_series(
                %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
            )
        """, (
            title, final_country, year_released, year_completed, 
            total_seasons, total_episodes, avg_runtime, 
            genres, platform, final_status, seasons_pre_log, tmdb_id
        ))
        
        conn.commit()
        print(f"\nSUCCESS: I've registered '{title}' to {final_country}.")
        
    except Exception as e:
        if 'conn' in locals(): conn.rollback()
        print(f"\nDATABASE ERROR: {e}")
    finally:
        if 'cur' in locals(): cur.close()
        if 'conn' in locals(): conn.close()

if __name__ == "__main__":
    add_series()
