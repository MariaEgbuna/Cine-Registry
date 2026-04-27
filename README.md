# A Database with a Brain

My database, called Cine Registry, is built using PostgreSQL. It makes tracking my movies and shows easy by doing the hard work for me. It uses smart rules to automatically update my watch status and keep track of my binge-watching habits. Instead of keeping messy manual records, I now have one strong and reliable place for all my data.

---
## The Architecture

I organized my data into three specific areas:

- Registry: Stores permanent details like titles, years, and directors.
- Watchlogs: Records my activity, including watch dates, ratings, and rewatch status.
- Archive: Acts as a backup "black box" that saves copies of any deleted data to keep my history safe.

### How it's wired (ERD)

![Cine_Registry ER Diagram](Images/ER%20Diagram.png)

| Component | Role | Why it exists |
| :--- | :--- | :--- |
| **`dates_table`** | The Calendar | A central timeline to track when I watch things. |
| **`series_metadata`** | The Show List | A master list of all my shows so there are no duplicates. |
| **`movie_metadata`** | The Film Vault | A list of all my movies registered to the db. No duplicates. |
| **`series_log`** | The Show Tracker | A record of my daily show watching. |
| **`movie_log`** | The Film Tracker | A record of when I watch each movie. |

### How it works

- **Easy Show Tracking**: I link the main show list to my logs using IDs. Because I use the ID instead of the title, I only have to set up the show details once. I can then track as many seasons or rewatches as I want without extra typing.
- **Accurate Dates**: Every entry connects to a calendar table. This makes it easy to create reports for any year.
- **Safety Records**: I have "audit" tables for everything. If I delete something by mistake, the system keeps a copy so I never lose my data.
- **Automatic Updates**: I use IDs from a movie database (TMDB). This helps my system talk to other sites to get info automatically.

---

## Keeping Data Correct and Automatic

This database approach stops manual work and reduces mistakes.

### 1. The Progress Protector
I created a rule called `fn_progress_protector`. When the number of episodes I have watched matches the total number of episodes in a show, the system automatically:

- Marks the show as 'Finished'.
- Adds an end date to the record.
This keeps my "Active" list clean without me needing to do it manually.

### 2. The Procedural "Write API"
I do not add data directly to the tables. Instead, I use special commands that act as a gateway:

- **add_series** / **add_movie**: Used to add a new show/movie. It makes sure the details are saved before I log any watchlog. This prevents errors where a watch session exists without a show/movie to link to.
- **series_watch**: Used for my daily updates. It manages everything, like starting a new season or updating the count, to keep my dashboard accurate.
- **movie_watch**: This has "smart" logic. It checks if I have already seen a movie. If I have, it automatically links the new watch and marks it as a rewatch.

### 3. The Python Gateway (Security)
I use Python scripts to help the database handle outside information.

- **Getting Info**: The scripts find details like genres and IDs from the movie website (TMDB) before sending the data to the database.
- **Keeping Secrets**: I use a hidden file (`.env`) for my passwords and keys. This keeps them off the internet and safe.
- **Cleaning Data**: Python checks the data first to make sure it is correct before it reaches the database.

---

## Deployment, Logic, and Operations

Ready to deploy the schema? Follow the step-by-step instructions to set up your PostgreSQL environment and Python metadata gateway:

- [Deployment & Setup Guide](Docs/getting_started.md)

If you want to see the "why" behind the code, check out these deep dives in the docs folder:

- [System Audit](Docs/system_audit.md): My approach to disaster recovery via JSONB snapshots and keeping the engine healthy.
- [View Architecture & Indexing](Docs/view_indexing.md): A look at how I use GIN indexes for fast genre searching and tiered views for Power BI.

---

## Tech Stack

- **Language:** SQL / PL/pgSQL, Python
- **Database:** PostgreSQL 17
- **APIs:** TMDB API
- **Tooling:** DBeaver, VS Code

---

*Maintained by Maria  
Self-Taught Analyst & SQL Enthusiast*
