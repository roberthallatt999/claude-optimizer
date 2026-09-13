---
paths:
  - "**/*.{php,js}"
---

# WordPress Security Rules

## Mandatory Security Practices

### 1. Output Escaping (REQUIRED for all output)

| Context | Function | Example |
|---------|----------|---------|
| HTML content | `esc_html()` | `<?php echo esc_html($title); ?>` |
| HTML attributes | `esc_attr()` | `<input value="<?php echo esc_attr($val); ?>">` |
| URLs | `esc_url()` | `<a href="<?php echo esc_url($link); ?>">` |
| JavaScript | `wp_json_encode()` | `var data = <?php echo wp_json_encode($data); ?>;` |
| CSS | `esc_attr()` | `style="color: <?php echo esc_attr($color); ?>;"` |
| Translations | `esc_html_e()` | `<?php esc_html_e('Text', 'domain'); ?>` |

### 2. Input Sanitization (REQUIRED for all input)

```php
// Text input
$name = sanitize_text_field($_POST['name']);

// Email
$email = sanitize_email($_POST['email']);

// URL
$url = esc_url_raw($_POST['url']);

// Integer
$id = absint($_POST['id']);

// HTML content (with allowed tags)
$content = wp_kses_post($_POST['content']);

// Filename
$file = sanitize_file_name($_POST['filename']);

// Slug
$slug = sanitize_title($_POST['slug']);

// Textarea
$text = sanitize_textarea_field($_POST['description']);
```

### 3. Nonce Verification (REQUIRED for all forms and actions)

```php
// In form
<form method="post">
    <?php wp_nonce_field('my_action', 'my_nonce'); ?>
    <!-- form fields -->
</form>

// Verification
if (!isset($_POST['my_nonce']) ||
    !wp_verify_nonce($_POST['my_nonce'], 'my_action')) {
    wp_die(__('Security check failed.', 'textdomain'));
}

// AJAX verification
check_ajax_referer('my_action', 'nonce');
```

### 4. Capability Checks (REQUIRED before privileged actions)

```php
// Check before action
if (!current_user_can('manage_options')) {
    wp_die(__('Unauthorized access.', 'textdomain'));
}

// In admin pages
if (!current_user_can('edit_posts')) {
    return;
}

// Specific post
if (!current_user_can('edit_post', $post_id)) {
    wp_die(__('You cannot edit this post.', 'textdomain'));
}
```

### 5. SQL Injection Prevention

```php
global $wpdb;

// ALWAYS use prepared statements
$results = $wpdb->get_results(
    $wpdb->prepare(
        "SELECT * FROM {$wpdb->prefix}table
         WHERE column = %s
         AND id = %d",
        $string_value,
        $integer_value
    )
);

// Placeholders:
// %s - string
// %d - integer
// %f - float

// For IN clauses
$ids = [1, 2, 3];
$placeholders = implode(', ', array_fill(0, count($ids), '%d'));
$query = $wpdb->prepare(
    "SELECT * FROM {$wpdb->posts} WHERE ID IN ($placeholders)",
    $ids
);
```

### 6. File Upload Security

```php
// Check file type
$allowed_types = ['image/jpeg', 'image/png', 'image/gif'];
$file_type = wp_check_filetype($file['name']);

if (!in_array($file['type'], $allowed_types)) {
    wp_die(__('Invalid file type.', 'textdomain'));
}

// Use WordPress upload functions
$upload = wp_handle_upload($file, ['test_form' => false]);

if (isset($upload['error'])) {
    wp_die($upload['error']);
}
```

## Security Checklist

Before committing code, verify:

- [ ] All user input is sanitized
- [ ] All output is escaped
- [ ] All forms have nonces
- [ ] All privileged actions check capabilities
- [ ] All database queries use prepared statements
- [ ] No sensitive data in error messages
- [ ] No debug output in production
- [ ] File uploads validate type and size
- [ ] AJAX handlers verify nonces and capabilities

## Common Vulnerabilities to Avoid

### Cross-Site Scripting (XSS)
```php
// WRONG
echo $_GET['search'];

// RIGHT
echo esc_html($_GET['search']);
```

### SQL Injection
```php
// WRONG
$wpdb->query("DELETE FROM table WHERE id = " . $_GET['id']);

// RIGHT
$wpdb->query($wpdb->prepare("DELETE FROM table WHERE id = %d", absint($_GET['id'])));
```

### Cross-Site Request Forgery (CSRF)
```php
// WRONG - no nonce
if (isset($_POST['delete'])) {
    delete_something();
}

// RIGHT - with nonce
if (isset($_POST['delete']) && wp_verify_nonce($_POST['nonce'], 'delete_action')) {
    delete_something();
}
```

### Broken Access Control
```php
// WRONG - no capability check
function delete_all_posts() {
    // deletes posts
}

// RIGHT - with capability check
function delete_all_posts() {
    if (!current_user_can('delete_posts')) {
        return false;
    }
    // deletes posts
}
```

## Security Headers

Add to theme's functions.php or mu-plugin:

```php
add_action('send_headers', function() {
    if (!is_admin()) {
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: SAMEORIGIN');
        header('X-XSS-Protection: 1; mode=block');
        header('Referrer-Policy: strict-origin-when-cross-origin');
    }
});
```
