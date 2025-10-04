-- Script SQL para crear la tabla 'memories' en Supabase
-- Ejecuta este script en el SQL Editor de Supabase Dashboard

-- 1. Crear la tabla memories
CREATE TABLE IF NOT EXISTS public.memories (
  nfc_uuid TEXT PRIMARY KEY,
  tipo TEXT NOT NULL CHECK (tipo IN ('historia', 'musica', 'imagen')),
  contenido TEXT NOT NULL
);

-- 2. Crear índice para búsquedas rápidas por UUID
CREATE INDEX IF NOT EXISTS idx_memories_nfc_uuid ON public.memories(nfc_uuid);

-- 3. Crear índice para búsquedas por tipo
CREATE INDEX IF NOT EXISTS idx_memories_tipo ON public.memories(tipo);

-- 4. Habilitar Row Level Security (RLS)
ALTER TABLE public.memories ENABLE ROW LEVEL SECURITY;

-- 5. Crear política para permitir lectura pública
CREATE POLICY "Permitir lectura pública de memories"
  ON public.memories
  FOR SELECT
  USING (true);

-- 6. Crear política para permitir inserción pública
CREATE POLICY "Permitir inserción pública de memories"
  ON public.memories
  FOR INSERT
  WITH CHECK (true);

-- 7. Crear política para permitir actualización pública
CREATE POLICY "Permitir actualización pública de memories"
  ON public.memories
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- 8. Crear política para permitir eliminación pública
CREATE POLICY "Permitir eliminación pública de memories"
  ON public.memories
  FOR DELETE
  USING (true);

-- (No se usan timestamps en esta versión simplificada)

-- Comentarios útiles
COMMENT ON TABLE public.memories IS 'Tabla para almacenar recuerdos asociados a tags NFC';
COMMENT ON COLUMN public.memories.nfc_uuid IS 'UUID único de la tarjeta NFC (Primary Key)';
COMMENT ON COLUMN public.memories.tipo IS 'Tipo de recuerdo: historia, musica o imagen';
COMMENT ON COLUMN public.memories.contenido IS 'Texto del recuerdo procesado por IA';
-- Nota: Ya no se almacena imagen_base64. Para tipo 'imagen' se regenerará dinámicamente usando el contenido (prompt).
