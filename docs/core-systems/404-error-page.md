---
id: 404-error-page
title: 404 Error Page
sidebar_position: 999
---

An entertaining, interactive custom 404 error page that turns the frustrating experience of hitting a dead link into a delightful user engagement opportunity.

## Overview

The custom 404 page replaces the default Docusaurus error page with an interactive, humorous experience featuring:

- **Animated Rainbow 404 Display** with CSS gradient animations
- **Rotating Excuse Generator** that cycles through funny explanations every 3 seconds
- **Interactive Cat Facts Spinner** with rotation animations
- **Emergency Navigation** with a Home button plus any configured links
- **Fake Statistics** displaying random "helpful" metrics
- **Absurd Troubleshooting Tips** mixing technical and creative "solutions"

## 🎨 Features

### Core Interactive Elements

1. **Rainbow Animated 404 Number**
   - Multi-color gradient background that shifts continuously
   - Large 8rem font size for maximum visual impact
   - CSS keyframe animation with 3-second cycle

2. **Excuse Generator™**
   - 15 humorous excuses that rotate automatically
   - Smooth transitions with 0.5s ease animation
   - Emoji-rich content for visual appeal

3. **Cat Facts Spinner**
   - Interactive button with rotation animation
   - Random cat facts that are tangentially related to the error
   - 1-second spin animation on click

4. **Emergency Navigation**
   - A Home button, plus any destinations passed via the `links` prop
   - Styled as prominent secondary buttons
   - Organized in a responsive button group

5. **Fun Statistics Cards**
   - Randomized "Pages Found Today" counter
   - "Robots Consulted" with fake numbers
   - "Coffee Consumed" by developers

### User Experience Features

- **Responsive Design**: Works seamlessly on all device sizes
- **Accessibility**: Proper ARIA labels and semantic HTML
- **Performance**: Lightweight with minimal JavaScript
- **Brand Consistency**: Uses site's design tokens and themes

## 📁 File Structure

```text
src/components/Custom404/
├── Custom404.tsx           # Shared 404 component (all the logic and UI)
└── index.ts                # Public exports, including the link types

src/theme/NotFound/Content/
└── index.tsx               # Docusaurus NotFound override; renders Custom404
```

## 🔧 Technical Implementation

### Component Architecture

The 404 system uses a modern reusable component architecture:

```tsx
// Reusable core component (v1.0)
export default function Custom404Component({
  links = []
}: Custom404ComponentProps): React.JSX.Element {
  const [excuse, setExcuse] = useState(0);
  const [isSpinning, setIsSpinning] = useState(false);
  const [catFact, setCatFact] = useState('');

  // Only links that named themselves in prose belong in the call to action
  const describedLinks = links.filter((link) => link.description);

  // Auto-rotating excuse system (EXCUSES is module-scoped, so no deps needed)
  useEffect(() => {
    const interval = setInterval(() => {
      setExcuse((prev) => (prev + 1) % EXCUSES.length);
    }, 3000);
    return () => clearInterval(interval);
  }, []);

  // Random cat fact initialization
  useEffect(() => {
    setCatFact(CAT_FACTS[Math.floor(Math.random() * CAT_FACTS.length)]);
  }, []);

  const handleSpinClick = () => {
    setIsSpinning(true);
    setTimeout(() => setIsSpinning(false), 1000);
    setCatFact(CAT_FACTS[Math.floor(Math.random() * CAT_FACTS.length)]);
  };

  // Enhanced render logic with accessibility
}
```

#### Navigation destinations

`links` defaults to none, so the only route the 404 page emits is `/`.

That default matters for sites built from this template. Only the site root is
guaranteed to exist everywhere: a consumer may serve its documentation from the
site root with `routeBasePath: '/'`, or disable the pages plugin entirely, in
which case routes such as `/docs` and `/demos` do not exist. Emitting them
anyway fails that consumer's build under `onBrokenLinks: 'throw'`.

Pass the routes your own site actually has:

```tsx
<Custom404
  links={[
    { to: '/docs', label: '📚 Read Docs', description: 'documentation' },
    { to: '/demos', label: '🎮 Try Demos', description: 'component demos' }
  ]}
/>
```

Each entry renders a button in the Emergency Navigation group. Adding
`description` also names the link in the closing call to action; entries without
one stay buttons only, and the sentence is omitted entirely when no link has a
description.

#### Theme-Level Integration (New in v1.0)

```tsx
// Theme NotFound Content component
import Custom404 from '../../../components/Custom404';

export default function ContentWrapper(): ReactNode {
  return (
    <>
      <Custom404 />
    </>
  );
}
```

This architecture provides:

- **Reusability**: One component, usable anywhere a 404 body is needed
- **Global Coverage**: Handles ALL 404s through theme integration
- **Component Isolation**: Separated logic from presentation

### CSS Animations

The page includes inline CSS animations for the rainbow effect:

```css
@keyframes rainbow {
  0% {
    background-position: 0% 50%;
  }
  50% {
    background-position: 100% 50%;
  }
  100% {
    background-position: 0% 50%;
  }
}
```

### State Management

- **excuse**: Index of currently displayed excuse (auto-increments)
- **isSpinning**: Boolean for button rotation animation
- **catFact**: Currently displayed cat fact (random selection)

## 🎭 Content Strategy

### Excuse Categories

The excuse generator includes diverse categories:

- **Animal-related**: Dogs eating pages, unicorns, dragons
- **Technology**: Robots, JavaScript, parallel dimensions
- **Pop culture**: Wizards, pirates, zombies, aliens
- **Absurd daily life**: Pizza runs, toilet paper shortages, circus acts

### Cat Facts Integration

Cat facts are chosen to be:

- Genuinely interesting but tangentially related to the error
- Light-hearted and maintaining the playful tone
- Educational while being entertaining

### Troubleshooting Humor

Divided into two categories:

- **Technical Solutions**: Parodies of real troubleshooting (restarting, blowing in cartridges)
- **Creative Solutions**: Completely absurd suggestions (interpretive dance, parallel universes)

## 🚀 Integration

### Docusaurus Integration

The 404 page integrates with Docusaurus through:

1. **Theme Override**: Swizzled at `src/theme/NotFound/Content`, which Docusaurus
   renders for every 404 — docs routes, page routes, and anything else that misses
2. **Layout**: Supplied by the theme's own `NotFound` wrapper upstream, so the
   component itself renders only the page body
3. **Link Component**: Uses `@docusaurus/Link` for internal navigation
4. **Theme Integration**: Respects the site's CSS custom properties

### NotFound Override

`src/theme/NotFound/Content/index.tsx` is the single entry point. It renders
`Custom404` and deliberately passes no `links` — see
[Navigation destinations](#navigation-destinations) for why, and for how to add
your own.

## 📊 Analytics Integration

The page includes engagement opportunities:

- Links to whatever destinations the site configures via `links`
- Call-to-action for exploring the site
- Fake but entertaining statistics that could be replaced with real analytics

## 🎨 Customization

### Easy Modifications

1. **Add New Excuses**: Extend the `EXCUSES` array
2. **Change Animation Timing**: Modify `useEffect` intervals
3. **Update Cat Facts**: Replace or extend the `CAT_FACTS` array
4. **Modify Statistics**: Change the random number generators
5. **Customize Colors**: Update the gradient in the rainbow animation

### Branding Customization

The page uses CSS custom properties for easy theming:

- `--ifm-color-primary`: For accent colors
- `--ifm-color-emphasis-*`: For text and background variations
- `--ifm-background-color`: For card backgrounds

## 🔗 Related Components

- **Layout**: Docusaurus theme layout wrapper
- **Link**: Internal navigation component
- **RelatedResources**: Can be added for additional navigation

## 🌟 Best Practices

### Performance

- Minimal JavaScript with efficient `useEffect` cleanup
- CSS animations instead of JavaScript animations
- Lazy loading of random content

### SEO & Accessibility

- Proper meta tags and title
- Semantic HTML structure
- Descriptive alt text and ARIA labels
- Keyboard navigation support

### User Experience

- Clear navigation options
- Entertaining content that reduces frustration
- Responsive design for all devices
- Fast loading with minimal dependencies

## 📝 Usage Example

Docusaurus routes every 404 through the `src/theme/NotFound/Content` override
automatically — no wiring required.

To render the same component elsewhere, import it directly and pass the routes
your site actually has:

```tsx
import Custom404, { type Custom404Link } from '@site/src/components/Custom404';

const links: Custom404Link[] = [
  { to: '/docs', label: '📚 Read Docs', description: 'documentation' }
];

export default function SomeErrorPage() {
  return <Custom404 links={links} />;
}
```

## 🔧 Configuration

The 404 page requires no configuration but can be customized through:

1. **Content Arrays**: Modify excuses and cat facts
2. **Timing Values**: Change animation and rotation intervals
3. **Styling**: Update CSS custom properties in your theme
4. **Navigation Links**: Pass a `links` array — see
   [Navigation destinations](#navigation-destinations)

This 404 page transforms a negative user experience into an opportunity for brand engagement, demonstrating attention to detail and user experience throughout the entire site.
