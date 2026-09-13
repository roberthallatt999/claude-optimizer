---
paths:
  - "**/*.{html,htm,twig,php}"
  - "**/{translations,lang,languages,i18n,locales}/**"
---

# Bilingual Content Rules (English/French)

These rules MUST be followed to ensure proper bilingual support for English and French content.

## Template Structure

### Conditional Language Blocks
- ✅ ALWAYS provide both English AND French versions
- ✅ Use `{if lang == 'en'}` and `{if:else}` structure
- ✅ Maintain identical HTML structure in both languages
- ❌ NEVER provide only one language version

**Correct:**
```html
{if lang == 'en'}
  <h1>Welcome to {{PROJECT_NAME}}</h1>
  <p>{{PROJECT_DESCRIPTION}}</p>
{if:else}
  <h1>Bienvenue à {{PROJECT_NAME_FR}}</h1>
  <p>{{PROJECT_DESCRIPTION_FR}}</p>
{/if}
```

**Incorrect:**
```html
<h1>Welcome to {{PROJECT_NAME}}</h1>  {* English only *}

{if lang == 'en'}
  <h1>Welcome</h1>
{/if}  {* Missing French version *}
```

### Page Metadata
- ✅ ALWAYS provide translated meta tags
- ✅ Translate page titles
- ✅ Translate meta descriptions
- ✅ Set correct lang attribute on HTML tag

**Correct:**
```html
{if lang == 'en'}
  {embed="_meta_tags"
    title="About Us - {{PROJECT_NAME}}"
    description="Learn about our organization and mission."
  }
  <html lang="en">
{if:else}
  {embed="_meta_tags"
    title="À Propos - {{PROJECT_NAME_FR}}"
    description="Apprenez-en davantage sur notre organisation et notre mission."
  }
  <html lang="fr">
{/if}
```

## Content Translation

### Text Content
- ✅ Translate ALL visible text
- ✅ Maintain meaning and tone across languages
- ✅ Use proper French grammar and accents
- ❌ NEVER use machine translation without review

**English to French Guidelines:**
- Use proper French accents: é, è, ê, à, ç, etc.
- Maintain formal tone (vous, not tu)
- Respect French grammar rules
- Use Canadian French conventions

### UI Elements
- ✅ Translate button text
- ✅ Translate form labels
- ✅ Translate placeholder text
- ✅ Translate error messages
- ✅ Translate navigation items

**Buttons:**
```html
{if lang == 'en'}
  <button class="px-6 py-3 text-white bg-brand-green">
    Learn More
  </button>
{if:else}
  <button class="px-6 py-3 text-white bg-brand-green">
    En savoir plus
  </button>
{/if}
```

**Form Labels:**
```html
{if lang == 'en'}
  <label for="email">Email Address</label>
{if:else}
  <label for="email">Adresse courriel</label>
{/if}
```

**Placeholders:**
```html
{if lang == 'en'}
  <input type="text" placeholder="Search resources..." />
{if:else}
  <input type="text" placeholder="Rechercher des ressources..." />
{/if}
```

### Alt Text and Accessibility
- ✅ Translate ALL alt text
- ✅ Translate ARIA labels
- ✅ Translate screen reader text

**Alt Text:**
```html
{if lang == 'en'}
  <img
    src="/images/child-checkup.jpg"
    alt="Healthcare provider examining a young child"
  />
{if:else}
  <img
    src="/images/child-checkup.jpg"
    alt="Professionnel de la santé examinant un jeune enfant"
  />
{/if}
```

**ARIA Labels:**
```html
{if lang == 'en'}
  <button aria-label="Close modal">
{if:else}
  <button aria-label="Fermer la fenêtre modale">
{/if}
```

## Language Switcher

### Language Toggle
- ✅ Provide clear language switching
- ✅ Indicate current language
- ✅ Make switcher accessible

**Language Switcher:**
```html
<nav class="language-switcher" aria-label="{if lang == 'en'}Language selection{if:else}Sélection de langue{/if}">
  {if lang == 'en'}
    <span class="font-bold" aria-current="true">English</span>
    <a href="{french_url}" lang="fr">Français</a>
  {if:else}
    <a href="{english_url}" lang="en">English</a>
    <span class="font-bold" aria-current="true">Français</span>
  {/if}
</nav>
```

### URL Structure
- ✅ Maintain separate URLs for each language
- ✅ Use language parameter or subdirectory
- ✅ Provide hreflang tags for SEO

**Hreflang Tags:**
```html
<link rel="alternate" hreflang="en" href="https://{{PROJECT_DOMAIN}}/en/about" />
<link rel="alternate" hreflang="fr" href="https://{{PROJECT_DOMAIN}}/fr/about" />
```

## Date and Number Formatting

### Dates
- ✅ Use appropriate date format for each language
- English: Month Day, Year (January 15, 2024)
- French: Day Month Year (15 janvier 2024)

**Date Formatting:**
```html
{if lang == 'en'}
  <time datetime="2024-01-15">January 15, 2024</time>
{if:else}
  <time datetime="2024-01-15">15 janvier 2024</time>
{/if}
```

### Numbers
- ✅ Use appropriate number formatting
- English: 1,234.56
- French: 1 234,56

## Content Management

### Channel Entries
- ✅ Use separate channel entries for each language
- ✅ OR use language-specific custom fields
- ✅ Link related content across languages

**Method 1: Separate Entries**
```html
{exp:channel:entries channel="pages" language="{lang}"}
  <h1>{title}</h1>
  <div>{body}</div>
{/exp:channel:entries}
```

**Method 2: Language Fields**
```html
<h1>{if lang == 'en'}{title_en}{if:else}{title_fr}{/if}</h1>
<div>{if lang == 'en'}{body_en}{if:else}{body_fr}{/if}</div>
```

## Common Phrases

### Standard Translations

**Navigation:**
- Home / Accueil
- About / À propos
- Resources / Ressources
- Contact / Nous joindre
- Search / Rechercher

**Actions:**
- Learn More / En savoir plus
- Read More / Lire la suite
- Submit / Soumettre
- Cancel / Annuler
- Save / Enregistrer
- Edit / Modifier
- Delete / Supprimer
- Download / Télécharger
- Print / Imprimer
- Share / Partager

**Form Elements:**
- First Name / Prénom
- Last Name / Nom de famille
- Email Address / Adresse courriel
- Phone Number / Numéro de téléphone
- Message / Message
- Required / Obligatoire

**Feedback Messages:**
- Success / Succès
- Error / Erreur
- Warning / Avertissement
- Information / Information
- Please wait... / Veuillez patienter...
- Loading... / Chargement...

**Time References:**
- Today / Aujourd'hui
- Yesterday / Hier
- Tomorrow / Demain
- This week / Cette semaine
- This month / Ce mois-ci
- This year / Cette année

**Accessibility:**
- Skip to main content / Passer au contenu principal
- Open menu / Ouvrir le menu
- Close menu / Fermer le menu
- Previous / Précédent
- Next / Suivant

## Typography and Formatting

### French Text Specifics
- ✅ Use proper French quotation marks: « guillemets »
- ✅ Add non-breaking space before: : ; ! ?
- ✅ Use proper French punctuation

**Correct Punctuation:**
```html
{if lang == 'en'}
  <p>Question: What is the answer?</p>
{if:else}
  <p>Question : Quelle est la réponse ?</p>
{/if}
```

### Capitalization
- English: Capitalize major words in titles
- French: Capitalize only first word and proper nouns

**Title Capitalization:**
```html
{if lang == 'en'}
  <h1>Resources for Healthcare Providers</h1>
{if:else}
  <h1>Ressources pour les professionnels de la santé</h1>
{/if}
```

## Testing Requirements

### Both Languages Must:
- ✅ Display correctly
- ✅ Have identical functionality
- ✅ Be fully accessible
- ✅ Have proper meta tags
- ✅ Have correct language attribute
- ✅ Work with screen readers

### Cross-Language Links
- ✅ Link to corresponding page in other language
- ✅ Preserve context when switching languages
- ✅ Use `lang` attribute on cross-language links

**Cross-Language Link:**
```html
{if lang == 'en'}
  <a href="{french_url}" lang="fr" class="text-brand-blue">
    Voir cette page en français
  </a>
{if:else}
  <a href="{english_url}" lang="en" class="text-brand-blue">
    View this page in English
  </a>
{/if}
```

## SEO Considerations

### Meta Tags
- ✅ Translate title tags
- ✅ Translate meta descriptions
- ✅ Use hreflang tags
- ✅ Create language-specific sitemaps

### Structured Data
- ✅ Include `inLanguage` property
- ✅ Provide translations in structured data

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "{if lang == 'en'}Article Title{if:else}Titre de l'article{/if}",
  "inLanguage": "{if lang == 'en'}en-CA{if:else}fr-CA{/if}",
  "alternativeHeadline": "{if lang == 'en'}Alternative Title{if:else}Titre alternatif{/if}"
}
</script>
```

## Anti-Patterns to Avoid

### ❌ NEVER Do These:

1. **English-only content**
   ```html
   ❌ <h1>Welcome</h1>  {* No French version *}
   ```

2. **Untranslated UI elements**
   ```html
   ❌ {if lang == 'en'}
        <button>Submit</button>
      {if:else}
        <button>Submit</button>  {* Same as English! *}
      {/if}
   ```

3. **Missing alt text translation**
   ```html
   ❌ <img alt="Child at doctor" />  {* Same alt in both languages *}
   ```

4. **Inconsistent structure**
   ```html
   ❌ {if lang == 'en'}
        <div class="container">
          <h1>Title</h1>
        </div>
      {if:else}
        <h1>Titre</h1>  {* Different HTML structure *}
      {/if}
   ```

5. **Machine translation without review**
   ```html
   ❌ {* Don't use Google Translate directly *}
   ```

6. **Missing language attribute**
   ```html
   ❌ <html>  {* Should have lang="en" or lang="fr" *}
   ```

## Validation Checklist

Before committing bilingual content:
- [ ] Both English and French versions present
- [ ] All UI elements translated
- [ ] Alt text translated
- [ ] ARIA labels translated
- [ ] Meta tags translated
- [ ] Identical HTML structure
- [ ] Proper French accents used
- [ ] Correct punctuation for each language
- [ ] Language attribute set correctly
- [ ] Tested in both languages
- [ ] Screen reader tested (both languages)
- [ ] Language switcher works
- [ ] Cross-language links functional
