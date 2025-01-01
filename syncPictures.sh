#!/bin/bash

# Pfade und Variablen
PHOTOS_LIBRARY="./Library.photoslibrary"
PHOTOS_DB="$PHOTOS_LIBRARY/database/Photos.sqlite"
EXPORT_DIR="./export"
CSV_FILE="$EXPORT_DIR/photo_album_mapping.csv"

# Zielverzeichnis erstellen
mkdir -p "$EXPORT_DIR"

# Ermitteln der Tabellen-Nummer für Alben (Z_ENT)
ALBUM_ENTITY=$(sqlite3 "$PHOTOS_DB" "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME='Album';")
FOLDER_ENTITY=$(sqlite3 "$PHOTOS_DB" "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME='Folder';")
ASSET_ENTITY=$(sqlite3 "$PHOTOS_DB" "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME='Asset';")
echo $ALBUM_ENTITY
RELATIONSHIP_TABLE="Z_${ALBUM_ENTITY}ASSETS"
echo $RELATIONSHIP_TABLE

# SQLite-Abfragen definieren
PHOTOS_QUERY="
SELECT 
    ZASSET.ZUUID, 
    ZADDITIONALASSETATTRIBUTES.ZORIGINALFILENAME, 
    ZASSET.ZDIRECTORY,
    ZASSET.ZLATITUDE,
    ZASSET.ZLONGITUDE
FROM ZASSET
LEFT JOIN ZADDITIONALASSETATTRIBUTES 
ON ZASSET.Z_PK = ZADDITIONALASSETATTRIBUTES.ZASSET;"

ALBUMS_QUERY="
SELECT 
    ZGENERICALBUM.ZTITLE, 
    ZASSET.ZUUID 
FROM ZGENERICALBUM
JOIN Z_${ALBUM_ENTITY}ASSETS 
ON ZGENERICALBUM.Z_PK = Z_${ALBUM_ENTITY}ASSETS.Z_${ALBUM_ENTITY}ALBUMS
JOIN ZASSET
ON Z_${ALBUM_ENTITY}ASSETS.Z_${ASSET_ENTITY}ASSETS = ZASSET.Z_PK;"

echo ALBUMS: 
echo $ALBUMS_QUERY
echo PHOTOS: 
echo $PHOTOS_QUERY

# Foto-Daten abrufen und in temporären Dateien speichern
PHOTOS_FILE=$(mktemp)
ALBUMS_FILE=$(mktemp)
sqlite3 "$PHOTOS_DB" "$PHOTOS_QUERY" > "$PHOTOS_FILE"
sqlite3 "$PHOTOS_DB" "$ALBUMS_QUERY" > "$ALBUMS_FILE"

echo ALBUMS: 
echo $ALBUMS_FILE
cat $ALBUMS_FILE

# Lege die Mapping-Datei an
echo "Photo UUID,Original Filename,Latitude,Longitude,Albums" > "$CSV_FILE"

# Fotos exportieren und Alben zuordnen
while IFS="|" read -r photo_uuid original_filename directory latitude longitude; do
    # Foto exportieren
    EXTENSION=${original_filename##*.}
    if [ "$EXTENSION" = "jpg" ]; then
        EXTENSION="jpeg"
    fi   
    ORIGINAL_PATH="$PHOTOS_LIBRARY/originals/$directory/$photo_uuid.$EXTENSION"
    DESTINATION_PATH="$EXPORT_DIR/$original_filename"

    if [[ -f "$ORIGINAL_PATH" ]]; then
        cp "$ORIGINAL_PATH" "$DESTINATION_PATH"
    else
        echo "WARNUNG: Foto $photo_uuid konnte nicht gefunden werden." >&2
        continue
    fi

    # Alben ermitteln, zu denen das Foto gehört
    ALBUMS=$(grep "|$photo_uuid$" "$ALBUMS_FILE" | cut -d'|' -f1 | tr '\n' ',' | sed 's/,$//')

    # Latitude und Longitude nur schreiben, wenn sie nicht -180.0 sind
    if [ "$latitude" = "-180.0" ]; then
        latitude=""
    fi
    if [ "$longitude" = "-180.0" ]; then
        longitude=""
    fi

    # Alben in CSV-Datei schreiben
    echo "$photo_uuid,$original_filename,$latitude,$longitude,\"$ALBUMS\"" >> "$CSV_FILE"
done < "$PHOTOS_FILE"

# Temporäre Dateien löschen
rm "$PHOTOS_FILE" "$ALBUMS_FILE"

echo "Export abgeschlossen. Fotos wurden in $EXPORT_DIR gespeichert. Mapping-Datei: $CSV_FILE"