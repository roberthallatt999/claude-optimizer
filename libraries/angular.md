# Angular Conventions (2026)

## Core Principles
- Prefer standalone components and signals-based APIs for new features.
- Keep services focused and injectable at the narrowest DI scope.
- Use strictly typed forms and route data with resolver guards.
- Separate smart containers from presentational components.

## Standalone Component
```ts
import { Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-product-card',
  standalone: true,
  imports: [CommonModule],
  template: `
    <article>
      <p>{{ name() }} — {{ subtotal() | currency }}</p>
      <button type="button" (click)="increase()">+1</button>
    </article>
  `,
})
export class ProductCardComponent {
  name = signal('Product');
  price = signal(19.99);
  quantity = signal(1);

  subtotal = () => this.price() * this.quantity();

  increase() {
    this.quantity.update((value) => value + 1);
  }
}
```

## Reactive Forms
```ts
import { FormBuilder, ReactiveFormsModule } from '@angular/forms';
import { Component } from '@angular/core';

@Component({
  selector: 'app-contact',
  standalone: true,
  imports: [ReactiveFormsModule],
  template: `
    <form [formGroup]="form" (ngSubmit)="submit()">
      <label>Email
        <input formControlName="email" type="email" />
      </label>
      <button type="submit" [disabled]="form.invalid">Submit</button>
    </form>
  `,
})
export class ContactFormComponent {
  constructor(private fb: FormBuilder) {}
  
  form = this.fb.group({
    email: [''],
  });

  submit() {
    if (this.form.invalid) return;
    // call API
  }
}
```

## Data + Routing
- Use `resolve` for SSR-safe preloading when needed.
- Prefer `inject()` in services/components for cleaner constructor usage.
- Keep route guards explicit (`canActivate`, `canMatch`) to avoid accidental access.

## Performance
- Add `ChangeDetectionStrategy.OnPush` on components that receive immutable inputs.
- Use `trackBy` on large `*ngFor` lists.
- Lazy-load feature modules/standalone route groups where boundaries are clear.

## Accessibility
- Use Angular `FormsModule` validation messages tied to `aria-describedby`.
- Ensure interactive controls expose text labels and keyboard behavior.
