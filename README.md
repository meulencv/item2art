# item2art

Aplicación Flutter que integra NFC, generación de contenido (Gemini), TTS/STT (ElevenLabs) y almacenamiento en Supabase.

## Configuración de variables de entorno

Se usan variables en un archivo `.env` (no se sube al repositorio) gestionadas con `flutter_dotenv`.

1. Copia el archivo `.env.example` a `.env`:
   
   ```bash
   copy .env.example .env  # Windows PowerShell
   ```
2. Rellena los valores reales:
   - `SUPABASE_URL` y `SUPABASE_ANON_KEY`: desde tu proyecto Supabase (Settings > API).
   - `ELEVENLABS_API_KEY`: desde https://elevenlabs.io
   - `GEMINI_API_KEY`: desde https://aistudio.google.com/app/apikey
   - `OPENROUTER_API_KEY`: (opcional) desde https://openrouter.ai
3. Ajusta modelos si lo deseas (variables `GEMINI_TEXT_MODEL`, `GEMINI_IMAGE_MODEL`, etc.)
4. Asegúrate de NO subir el archivo `.env` (listado en `.gitignore`).

### Ejemplo de `.env`

```
SUPABASE_URL=https://TU_PROYECTO.supabase.co
SUPABASE_ANON_KEY=xxxxx
ELEVENLABS_API_KEY=xxxxx
ELEVENLABS_VOICE_ID=JBFqnCBsd6RMkjVDRZzb
GEMINI_API_KEY=xxxxx
OPENROUTER_API_KEY=xxxxx
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
GEMINI_TEXT_MODEL=gemini-2.5-flash
GEMINI_IMAGE_MODEL=gemini-2.5-flash-image
ELEVENLABS_TTS_MODEL=eleven_multilingual_v2
ELEVENLABS_STT_MODEL=eleven_turbo_v2
```

## Ejecución

Instala dependencias y ejecuta:

```bash
flutter pub get
flutter run
```

Si ves un error indicando que faltan variables (por ejemplo en Supabase), revisa que `.env` esté presente y con valores.

## Seguridad

- Nunca publiques tus claves reales.
- Regenera una clave si accidentalmente se expuso.
- Considera un backend proxy para operaciones sensibles en producción.

## Próximos pasos

- Añadir pruebas unitarias para servicios.
- Manejo de errores más robusto y UI para estados de carga.

---
Generado con soporte de automatización para centralizar credenciales de forma segura.
