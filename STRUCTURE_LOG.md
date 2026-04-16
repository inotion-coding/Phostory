# Phostory Product Specification & Structure Log

This document provides a comprehensive overview of the Phostory web application's current architecture, features, and technical specifications. It is designed to serve as a complete reference for any future development or debugging, especially when using AI coding assistants.

---

## 1. Project Architecture
Phostory is a modern Single Page Application (SPA) built with a minimalist, high-performance approach.

- **Frontend**: Vanilla HTML5, CSS3, and JavaScript (ES Modules).
- **Backend Services**: Supabase (PostgreSQL, Auth, Storage).
- **Design Philosophy**: Glassmorphism, premium typography (Outfit), and responsive masonry layouts.

---

## 2. File Structure
- `index.html`: The structural backbone containing all view containers (Home, About, Make, Share, Profile, Settings). It references `script.js` as a module.
- `script.js`: **[CORE LOGIC]** Contains all application logic, including Supabase client initialization, authentication handlers, SPA routing (`switchView`), and the Masonry Grid engine.
- `style.css`: The central design system containing glassmorphism effects, responsive grid logic, and micro-animations.
- `404.html`: Essential for GitHub Pages hosting; handles redirection for SPA deep links.
- `DEVELOPMENT_LOG.md`: Historical record of development milestones and significant refactors.
- `STRUCTURE_LOG.md`: This document (Technical & Functional reference).

---

## 3. UI/UX Map (Views)
The application dynamically switches between views using a `switchView()` system defined in `script.js`.

### A. Navigation & Header
- **Logo**: Clicking returns user to Home.
- **Hamburger Menu**: Dropdown navigation for all features (`id="menuToggle"`, `id="dropdownMenu"`).

### B. Home View (`#homeView`)
- **Discovery Grid**: Infinite/Masonry layout for public photos (`id="masonryGrid"`).
- **Filter Chips**: 
    - `All Stories`: Default public view.
    - `My Likes`: Posts liked by the current authenticated user.
    - `Best`: (Top Liked) Trending content.

### C. About Us View (`#aboutView`)
- Brand story and mission statement for Phostory.

### D. Make My Phostory (`#makeView`)
- **Upload Form**: Title, Image upload (drag/drop), Visibility toggle (Public/Private).
- **My Uploads List**: Mini masonry grid to manage personal posts with Edit/Delete capabilities.

### E. Share My Phostory (`#shareView`)
- **Profile Link**: Copyable link using clean URL routing (e.g., `phostory.studio/username`).
- **Profile Customization**: Bio editing and Avatar upload.
- **Public Preview**: Live mockup of the user's public profile page.

### G. Settings View (`#settingsView`)
- **Account Management**: Change unique @username and Update Password.
- **Danger Zone**: Permanent account deletion.

### H. Public Profile View (`#profilePageView`)
- Dynamic view triggered by the URL path or params. Displays user-specific photo collections.

---

## 4. Feature Specifications

### 🔑 Authentication
- **ID-Based Ecosystem**: Users register with a unique @username. Auth logic in `script.js` manages both ID and email-based login flows.
- **Role Management**: Supports roles like `operator`, `admin`, and `user` for management features.

### 🖼️ Content Management
- **Responsive Masonry**: Adaptive grid that redistributes items based on viewport width (2 to 6+ columns).
- **Visibility Control**: 
    - `Public`: Appear in the global discovery feed.
    - `Private`: Appear only on the personal share link.
- **Interactions**: Persistent "Like" system with optimistic UI updates.

### 📱 Mobile Optimization
- **Flicker-Free Grid**: Specialized handling for mobile browser UI changes (address bar resizing) to prevent unintentional layout jumps.
- **Reveal on Tap**: Photo metadata is revealed via touch interactions on mobile.

---

## 5. Backend & Database Schema (Supabase)

### 📊 Tables
- **`profiles`**: User metadata, usernames, bios, and avatar references.
- **`posts`**: Photographic content, titles, and visibility settings.
- **`likes`**: Junction table for user-post interactions.

### 📁 Storage Buckets
- `public_photos`: Post images with public access.
- `private_photos`: Post images restricted to certain views.
- `profiles`: User-uploaded profile pictures.

---

## 6. Technical Configuration
- **Supabase URL**: `https://jlxlccrhwmmrubvgyloi.supabase.co`
- **External Assets**: Google Fonts (Outfit), Supabase JS SDK (ESM).
- **Routing**: Employs a hybrid of URL search params and pathname restoration for GitHub Pages compatibility.

---
*Last Updated: 2026-04-16*
