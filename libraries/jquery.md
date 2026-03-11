# jQuery Conventions (Legacy)

## Core Principles
- Keep jQuery usage minimal and contained to legacy code.
- Replace direct DOM manipulation with event delegation and cached selectors.
- Migrate isolated interactions to modern framework modules where possible.

## Safe Patterns
```js
const $form = $('#contact-form');
const $submit = $form.find('[type="submit"]');

$form.on('submit', function (event) {
  event.preventDefault();
  const payload = {
    email: $form.find('[name="email"]').val(),
    message: $form.find('[name="message"]').val(),
  };

  $submit.prop('disabled', true).text('Sending...');

  $.ajax({
    url: '/api/contact',
    method: 'POST',
    contentType: 'application/json',
    data: JSON.stringify(payload),
    success() {
      $form.trigger('reset');
    },
    complete() {
      $submit.prop('disabled', false).text('Send');
    },
  });
});
```

## Event Delegation
```js
$(document).on('click', '[data-toggle]', function () {
  const target = $($(this).data('target'));
  target.toggleClass('is-open');
});
```

## Best Practices
- Prefer delegated events for repeated/dynamic elements.
- Keep selectors cached for performance.
- Avoid chaining many DOM reads/writes; batch updates where possible.
