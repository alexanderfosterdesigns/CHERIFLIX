# Cheriflix Beta repository requirements

- This branch/repository represents the **Cheriflix Beta** version.
- Android and Android TV builds must display the installed application name exactly as **Cheriflix Beta**.
- Do not change the Android application/package ID unless a genuine technical requirement has been explicitly approved. The visible application name and package identifier are separate concerns.
- Future changes must preserve the existing movie and TV content-loading behaviour, including APIs, endpoints, query construction, data sources, routing, transformations, pagination, loading triggers, result ordering, filtering semantics, and authentication, unless an alteration is explicitly authorised.
- After implementation work that changes the app, build a final signed, installable Android TV-compatible release APK.
- Create the repository folder `ready to install apk` if it does not exist.
- Remove or replace obsolete APKs in that folder and place the final build at `ready to install apk/Cheriflix-Beta.apk`.
- The APK in that folder must be the final ready-to-install build, not an intermediate or debug artefact, unless a debug build is explicitly requested.
- Before declaring implementation complete, verify:
  - the release APK builds successfully;
  - APK signing is valid;
  - the installed/displayed name is **Cheriflix Beta**;
  - the Android TV launcher activity and banner still work;
  - intended Android ABIs are packaged;
  - existing movie and TV loading behaviour remains unchanged; and
  - the final APK exists in `ready to install apk`.
