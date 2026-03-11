# Material UI (MUI) Conventions (2026)

## Core Principles
- Use MUI component APIs consistently and prefer composition over custom one-off UI.
- Use the theme system for spacing, color, typography, and density over inline style overrides.
- Prefer `sx` for localized, typed style tweaks and `styled`/custom components for reusable patterns.

## Layout and Theming
```tsx
import { AppBar, Box, Container, Typography } from '@mui/material';
import { ThemeProvider, createTheme } from '@mui/material/styles';

const theme = createTheme({
  palette: {
    primary: { main: '#0050ff' },
  },
  spacing: 8,
});

export function SiteHeader() {
  return (
    <ThemeProvider theme={theme}>
      <AppBar position="static">
        <Container>
          <Typography variant="h6">App Name</Typography>
        </Container>
      </AppBar>
      <Box mt={2}>
        <Container maxWidth="md">Content</Container>
      </Box>
    </ThemeProvider>
  );
}
```

## Forms
```tsx
import { Button, TextField, Stack } from '@mui/material';

function ContactForm() {
  return (
    <form>
      <Stack spacing={2}>
        <TextField label="Email" type="email" required />
        <TextField label="Message" multiline minRows={4} />
        <Button type="submit" variant="contained" color="primary">
          Send
        </Button>
      </Stack>
    </form>
  );
}
```

## Accessibility and UX
- Use `label`, `id`, and helper text patterns from MUI form controls.
- Keep focus order predictable; test keyboard interactions on dialogs and menus.
- Ensure `aria-*` attributes are passed through props when creating custom wrappers.

## Performance and Data
- Use lightweight lazy imports for rarely used components.
- Memoize large dialog/list data and keep prop references stable to reduce rerenders.
- Co-locate loading/error states in component state, not in global layout unless shared.
