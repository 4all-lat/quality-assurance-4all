# Diagramas — Pipeline QA 4All

`qa-pipeline-4all.drawio` es un único fichero draw.io (XML sin comprimir) con **11 pestañas**, una por
etapa o grupo de etapas del pipeline descrito en [`../SKILL.md`](../SKILL.md).

## Pestañas

| Pestaña | Contenido | Fases cubiertas |
|---------|-----------|-----------------|
| `00 · Pipeline QA (11 fases)` | Vista general: las 11 fases, sus gates y los 4 bloques (definición, construcción, validación no funcional, entrega) | 1–11 |
| `01 · Pirámides de calidad y de tests` | Capas de calidad, pirámide de tests 70/20/10 y anti-patrones (invertida, reloj de arena) | Transversal |
| `02 · Fase 1 — Especificación (SDD)` | La spec como fuente de verdad, derivaciones y plantilla de 7 secciones | 1 |
| `03 · Fases 2-3 — TDD y BDD` | Ciclo Red/Green/Refactor, qué testear a nivel unitario, Gherkin y step definitions | 2, 3 |
| `04 · Fase 4 — Integración y contratos` | Niveles in-memory y live, matriz endpoint × tenant, Pact y OpenAPI | 4 |
| `05 · Fase 5 — Property-based testing` | Propiedades, generación aleatoria, shrinking y propiedades típicas | 5 |
| `06 · Fase 6 — Seguridad (OWASP API Top 10)` | Los 10 riesgos con su test + SQLi, XSS, path traversal y métodos HTTP | 6 |
| `07 · Fases 7-9 — Rendimiento, cobertura y mutación` | Métricas P50/P95/P99, umbral de cobertura y mutation score | 7, 8, 9 |
| `08 · Fase 10 — Estratificación y CI` | Smoke / Regression / Full, categorización por stack y pipeline | 10 |
| `09 · Fase 11 — Producción` | Checklist pre-producción, SLOs con alertas, post-despliegue y sign-off | 11 |
| `10 · Prácticas transversales y anti-patrones` | Flaky, datos de test, a11y, regresión visual, code review, DoD y anti-patrones | Transversal |

## Cómo abrirlo

- **Web**: [app.diagrams.net](https://app.diagrams.net) → *Open Existing Diagram* → seleccionar el fichero.
- **Escritorio**: draw.io / diagrams.net, o la extensión de VS Code *Draw.io Integration*.
- **CLI** (exportar a PNG/SVG/PDF sin abrir la app):

  ```bash
  # requiere el binario drawio-desktop o el contenedor rlespinasse/drawio-export
  drawio -x -f svg -o qa-pipeline-4all.svg diagrams/qa-pipeline-4all.drawio --all-pages
  ```

El fichero es XML plano y versionable: los diffs se leen en el repositorio, a diferencia del formato
`.drawio` comprimido.

## Mantenimiento

Si cambia un gate o una métrica en `SKILL.md` o en `references/`, actualiza la pestaña correspondiente
del diagrama en el mismo cambio. `tests/cases/docs.diagrams.test.sh` lo vigila: el fichero debe seguir
siendo XML bien formado con 11 pestañas, sin ids duplicados, con los presupuestos de tier canónicos
(30 s / 5 min / 15 min) y sin afirmaciones que los documentos ya hayan retirado. Las fuentes de cada cifra son:

- gates y checklists → [`../references/quality-gates.md`](../references/quality-gates.md)
- seguridad → [`../references/owasp-api-testing.md`](../references/owasp-api-testing.md)
- pirámide y estratificación → [`../references/test-pyramid.md`](../references/test-pyramid.md)
- contratos → [`../references/contract-testing.md`](../references/contract-testing.md)
- rendimiento → [`../references/performance-testing.md`](../references/performance-testing.md)
- prácticas y SLOs de release → [`../references/quality-engineering-practices.md`](../references/quality-engineering-practices.md) y [`../assets/pre-production-checklist.md`](../assets/pre-production-checklist.md)
