# De Anza College Website Template

A modern, responsive website template for De Anza College featuring an interactive campus map and comprehensive information display.

## Features

### 🎨 Modern Design
- Clean, professional design with De Anza College branding
- Responsive layout that works on all devices
- Smooth animations and transitions
- Modern color scheme with blue accent colors

### 🗺️ Interactive Campus Map
- Clickable building markers with detailed information
- Search functionality to find specific buildings or services
- Color-coded legend for different building types
- Modal popups with building details, hours, and services

### 📱 Mobile-First Responsive Design
- Mobile hamburger navigation
- Optimized layouts for tablets and phones
- Touch-friendly interactive elements
- Responsive grid systems

### 📋 Information Sections
- Campus hours and contact information
- Transportation details
- Student services overview
- Contact form with validation

### ⚡ Interactive Features
- Smooth scrolling navigation
- Form validation and notifications
- Search functionality
- Hover effects and animations

## File Structure

```
├── index.html          # Main HTML file
├── styles.css          # CSS styles and responsive design
├── script.js           # JavaScript functionality
└── README.md           # This file
```

## Getting Started

1. **Download the files** to your local machine
2. **Open `index.html`** in your web browser
3. **Customize the content** as needed (see customization section below)

## Customization Guide

### Updating College Information

#### Contact Information
Edit the contact details in `index.html`:
```html
<!-- In the contact section -->
<div class="contact-item">
    <i class="fas fa-phone"></i>
    <div>
        <h4>Phone</h4>
        <p>(408) 864-5678</p>  <!-- Update this -->
    </div>
</div>
```

#### Campus Hours
Update the hours in the information cards:
```html
<!-- In the info section -->
<div class="info-card">
    <div class="info-icon">
        <i class="fas fa-clock"></i>
    </div>
    <h3>Hours of Operation</h3>
    <p>Monday - Friday: 8:00 AM - 10:00 PM<br>  <!-- Update these -->
    Saturday: 9:00 AM - 5:00 PM<br>
    Sunday: Closed</p>
</div>
```

### Adding/Modifying Map Buildings

#### 1. Update Building Information in `script.js`
```javascript
const buildingInfo = {
    'your-building': {
        name: 'Your Building Name',
        description: 'Description of the building',
        hours: 'Operating hours',
        services: ['Service 1', 'Service 2', 'Service 3']
    }
    // Add more buildings here
};
```

#### 2. Add Building Markers in `index.html`
```html
<div class="map-building" data-building="your-building">
    <div class="building-marker academic"></div>  <!-- Choose color class -->
    <span>Building Name</span>
</div>
```

#### 3. Available Color Classes
- `academic` - Blue (#3b82f6)
- `admin` - Green (#10b981)
- `parking` - Orange (#f59e0b)
- `services` - Red (#ef4444)

### Changing Colors and Styling

#### Primary Colors
Update the color scheme in `styles.css`:
```css
/* Primary blue color */
:root {
    --primary-color: #1e40af;  /* Change this */
    --secondary-color: #3b82f6; /* Change this */
}
```

#### Fonts
Change the font family in `styles.css`:
```css
body {
    font-family: 'Your Font', sans-serif;  /* Update this */
}
```

### Adding Real Map Integration

To integrate with Google Maps or other mapping services:

1. **Replace the placeholder map** in the HTML:
```html
<div id="campusMap" class="campus-map">
    <!-- Replace with actual map embed code -->
    <iframe src="your-map-url"></iframe>
</div>
```

2. **Update the JavaScript** to work with the real map API
3. **Add map markers** using the mapping service's API

## Browser Support

- ✅ Chrome (latest)
- ✅ Firefox (latest)
- ✅ Safari (latest)
- ✅ Edge (latest)
- ✅ Mobile browsers

## Performance Features

- Optimized CSS with efficient selectors
- Minimal JavaScript for fast loading
- Responsive images and icons
- Smooth animations using CSS transforms

## Accessibility Features

- Semantic HTML structure
- Proper heading hierarchy
- Alt text for images
- Keyboard navigation support
- Screen reader friendly

## Future Enhancements

Potential improvements you could add:

1. **Real-time data integration** (bus schedules, parking availability)
2. **User accounts** for personalized experience
3. **Multi-language support**
4. **Advanced search filters**
5. **Virtual campus tour**
6. **Event calendar integration**
7. **Weather information**
8. **Emergency notifications**

## Support

For questions or customization help:
- Review the code comments for guidance
- Check browser console for any errors
- Ensure all files are in the same directory
- Verify that external resources (fonts, icons) are loading

## License

This template is provided as-is for educational and development purposes. Feel free to modify and use for your De Anza College website project.

---

**Note**: This is a template that uses placeholder content and images. Replace all placeholder content with actual De Anza College information before deploying to production. 