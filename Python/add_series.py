"""
================================================================================
MODULE: Focus Destroyer - My Series Registry Engine
DATABASE: PostgreSQL (focus_destroyer)
SCHEMA: the_receipts_sandbox
CORE FUNCTION: register_new_series()
================================================================================
I designed this module to be the "Architect" of my TV library. Since TV shows are 
complex—evolving through seasons, network moves, and status changes—I built this 
to automate the heavy lifting while keeping me in total control of the data.

MY LOGIC ARCHITECTURE:

    1. THE "SNIPER" SEARCH SYSTEM:
       I added a dual-mode entry. I can search by title (which gives me a top-5 
       selection menu to avoid remake confusion) or I can use the "Sniper Mode" 
       by entering a direct TMDB ID. This was essential for fixing those 
       stubborn "split" franchises like Total Drama.

    2. DUPLICATE PROTECTION:
       Before any data is committed, I check 'series_metadata' for the tmdb_id. 
       If it's already there, the script kills the process. This keeps my 
       'v_series_dashboard' clean and prevents me from polluting my sandbox 
       with redundant entries.

    3. SMART STATUS MAPPING:
       TMDB's status labels can be messy. I built a translator that funnels 
       everything into my four core categories: 'Returning', 'Ended', 
       'Cancelled', or 'TBD'. It's my early warning system for show renewals.

    4. RUNTIME & COUNTRY HEURISTICS:
       -> Runtime: Since TV lengths fluctuate, I designed a fallback that 
          averages the runtime list or grabs the most recent episode length.
       -> Country: To solve the "Orphan Black" dilemma, I added a verification 
          step. The API suggests the origin, but I get the final override.

    5. THE LEGACY OVERRIDE (PRE-LOG):
       I included a 'seasons_pre_log' prompt. This is for the shows I've been 
       watching for years before I built Focus Destroyer. It ensures my 
       completion stats are accurate even for shows I'm halfway through.

    6. PROCEDURE-BASED COMMIT:
       This doesn't just push data; it calls my PostgreSQL Stored Procedure 
       (add_series). This lets the DB handle the logic of firing the 
       'series_code' generator and updating the audit logs in one clean shot.
================================================================================
"""

# --- IMPORTS ---
import requests
import psycopg2
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
def register_new_series():
    # --- Step 1: TITLE OR ID SEARCH ---
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
    
    # --- Step 2: FETCH DEEP METADATA ---
    detail_params = {"api_key": TMDB_API_KEY, "language": "en-US"}
    d = requests.get(f"https://api.themoviedb.org/3/tv/{tmdb_id}", params=detail_params, timeout=10).json()
    
    title = d.get('name') # Get the official title from TMDB
    year_released = int(d.get('first_air_date', '0000')[:4]) # Extract year from first air date
    print(f"\nTargeting: {title} ({year_released})") # Confirming the title and year for user clarity
    
    confirm = input("Is this the correct show? (y/n): ").strip().lower()
    if confirm != 'y':
        print("Aborting registration.")
        return

    # --- Step 3: MAPPING DATA ---
    api_countries = d.get('origin_country', []) # This is a list of country codes (e.g., ['US', 'CA'])
    detected_country = api_countries[0] if api_countries else '??' # Default to '??' if no country info is available
    
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

    # --- Step 4: DB CONNECTION AND COMMIT (LATE OPEN) ---
    try:
        conn = psycopg2.connect(**DB_PARAMS)
        cur = conn.cursor()

        # Duplicate Check
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
    register_new_series()