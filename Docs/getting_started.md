# Deployment and Setup Guide

This guide explains how to set up the `cine_registry` database and the Python tools.

### 1. Database Setup
To make sure everything works correctly, run the SQL files in this exact order:

1. `01_schema.sql`: Sets up the tables and rules.
2. `02_triggers.sql`: Sets up the automation.
3. `03_procedures.sql`: Sets up the commands I use to add data.
4. `04_sample_data.sql`: Adds test data to check that everything works.

### 2. Testing and Verification
The sample data script does more than just add info; it checks that the system works as expected.

* **Registering Shows:** Test the `add_series` command with the show "The Bear". Check the table to make sure the system automatically created a unique ID for it.
* **Progress Tracker:** Test the `series_watch` command with the show "Severance":
    * If you have only watched 4 of 9 episodes, the status stays as "Watching."
    * When you log all 9 episodes, the system automatically changes the status to "Finished" and adds the date.
* **Timeline Handling:** My `movie_watch` and `series_watch` commands allows to add data for different dates easily.

### 3. Smart Rewatch Detection
When I log a movie like "Inception," the system acts like a detective. If it sees that I have already watched that movie, it automatically links it to the original record and marks it as a rewatch. This keeps my history organized without me having to label it manually.

---

## 2. Python Setup

The Python layer does the heavy work for the Cine Registry. It fetches extra details (like genres) from the movie website (TMDB) and makes sure the data is clean and safe before it goes into the database.

### Install Dependencies

To set up the tools, run this command in your terminal:

```bash
pip install -r requirements.txt
```

### Environment Variables

Create a file named **.env** in your main folder. 

> Note: This file is ignored by GitHub so your private keys and passwords stay safe.

```env
TMDB_API_KEY=your_key
DB_NAME=cine_registry
DB_SCHEMA=entries
DB_USER=your_user
DB_PASSWORD=your_password
DB_HOST=localhost
DB_PORT=5432
```

### Usage

Run these tools from your command line to fetch data and save it to your database. These scripts do the hard work for you by getting info from the internet first.

- `python movie_logger.py`: This searches for a movie on TMDB to get details like its genre and length. It then sends that info to the `movie_watch` command to save your viewing record.
- `python add_series.py`: This sets up a new show. It pulls official details, such as the total number of seasons, and sends them to the `add_series` command to register the show in your library.

---

### 3. API Key Setup

My Python tools need to connect to The Movie Database (TMDB) to automatically grab details like movie length, genres, etc.

1. **Sign Up:** Go to [themoviedb.org](https://www.themoviedb.org/) and create a free account.
2. **Get Your Key:** Go to your account settings, find the "API" section, and create a new **API Read Access Token** or **API Key**.
3. **Save It:** Add this key to your `.env` file where it says `TMDB_API_KEY`.

> **Security Tip:** Your API key is private, just like a password. Never share it. Since your `.env` file is hidden from GitHub, your key will stay safe on your own computer.

---

*Getting Started*  
*Maintained by Maria*  
*Focus on Database Reliability & Integrity*
