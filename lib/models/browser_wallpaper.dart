import 'package:flutter/material.dart';

class BrowserWallpaper {
  const BrowserWallpaper({
    required this.id,
    required this.name,
    required this.category,
    this.url,
    this.solidColor,
    this.subtitle,
    this.tag,
    this.proceduralId,
  });

  /// Set for wallpapers painted in code (see CinderWallpapers).
  final String? proceduralId;

  final String id;
  final String name;
  final String category;
  final String? url;
  final Color? solidColor;
  final String? subtitle;
  final String? tag;

  /// Returns a lightweight thumbnail version of the URL for instant grid loading.
  String? get thumbnailUrl {
    if (url == null) return null;
    if (url!.contains('picsum.photos')) {
      return url!.replaceAll('/1920/1080', '/400/225');
    }
    if (url!.contains('images.unsplash.com')) {
      return url!.replaceAll('w=2400', 'w=520').replaceAll('q=80', 'q=60');
    }
    return url;
  }
}


const List<BrowserWallpaper> kWallpapers = <BrowserWallpaper>[
  // --- Cinder originals (painted in code: private, instant, offline) ---
  BrowserWallpaper(id: 'cinder-ember', name: 'Ember', category: 'Cinder originals', subtitle: 'Cinder’s signature: glowing coals in the dark.', tag: '✦ Original', proceduralId: 'ember'),
  BrowserWallpaper(id: 'cinder-aurora', name: 'Aurora', category: 'Cinder originals', subtitle: 'Northern lights over a polar night.', tag: '✦ Original', proceduralId: 'aurora'),
  BrowserWallpaper(id: 'cinder-dusk', name: 'Dusk', category: 'Cinder originals', subtitle: 'The last light of a violet evening.', tag: '✦ Original', proceduralId: 'dusk'),
  BrowserWallpaper(id: 'cinder-abyss', name: 'Abyss', category: 'Cinder originals', subtitle: 'Light filtering down into deep water.', tag: '✦ Original', proceduralId: 'abyss'),
  BrowserWallpaper(id: 'cinder-nebula', name: 'Nebula', category: 'Cinder originals', subtitle: 'A stellar nursery in pink and blue.', tag: '✦ Original', proceduralId: 'nebula'),
  BrowserWallpaper(id: 'cinder-mist-forest', name: 'Mist Forest', category: 'Cinder originals', subtitle: 'Green shade and morning haze.', tag: '✦ Original', proceduralId: 'mist-forest'),
  BrowserWallpaper(id: 'cinder-sakura', name: 'Sakura', category: 'Cinder originals', subtitle: 'Soft blossom pinks, light and airy.', tag: '✦ Original', proceduralId: 'sakura'),
  BrowserWallpaper(id: 'cinder-golden-hour', name: 'Golden Hour', category: 'Cinder originals', subtitle: 'Warm sun low on the horizon.', tag: '✦ Original', proceduralId: 'golden-hour'),
  BrowserWallpaper(id: 'cinder-neon-city', name: 'Neon City', category: 'Cinder originals', subtitle: 'Cyan and magenta after midnight.', tag: '✦ Original', proceduralId: 'neon-city'),
  BrowserWallpaper(id: 'cinder-glacier', name: 'Glacier', category: 'Cinder originals', subtitle: 'Cold, bright and perfectly clear.', tag: '✦ Original', proceduralId: 'glacier'),
  BrowserWallpaper(id: 'cinder-lava', name: 'Lava Flow', category: 'Cinder originals', subtitle: 'Molten orange, red and gold.', tag: '✦ Original', proceduralId: 'lava'),
  BrowserWallpaper(id: 'cinder-cosmic', name: 'Cosmic Violet', category: 'Cinder originals', subtitle: 'Deep space with violet and teal glow.', tag: '✦ Original', proceduralId: 'cosmic'),
  BrowserWallpaper(id: 'cinder-dune', name: 'Desert Dune', category: 'Cinder originals', subtitle: 'Sand, sun and long shadows.', tag: '✦ Original', proceduralId: 'dune'),
  BrowserWallpaper(id: 'cinder-orchid-night', name: 'Orchid Night', category: 'Cinder originals', subtitle: 'Soft magenta bloom in the dark.', tag: '✦ Original', proceduralId: 'orchid-night'),
  BrowserWallpaper(id: 'cinder-peach-haze', name: 'Peach Haze', category: 'Cinder originals', subtitle: 'A gentle apricot-to-lilac wash.', tag: '✦ Original', proceduralId: 'peach-haze'),
  BrowserWallpaper(id: 'cinder-tideline', name: 'Tideline', category: 'Cinder originals', subtitle: 'Turquoise shallows meeting deep blue.', tag: '✦ Original', proceduralId: 'tideline'),

  // --- Landscapes (curated photography) ---
  BrowserWallpaper(
    id: 'photo-granite-meadow',
    name: 'Granite Meadow',
    category: 'Landscapes',
    subtitle: 'Sunlit meadow beneath a granite wall.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1426604966848-d7adac402bff?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-redwood-trail',
    name: 'Forest Trail',
    category: 'Landscapes',
    subtitle: 'Light falling through tall forest trees.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-glacier-valley',
    name: 'Glacier Valley',
    category: 'Landscapes',
    subtitle: 'Snow peaks above a wide valley.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-misty-ridge',
    name: 'Misty Ridge',
    category: 'Landscapes',
    subtitle: 'Layers of mist over green ridges.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-highland-clouds',
    name: 'Highland Clouds',
    category: 'Landscapes',
    subtitle: 'Sunset breaking over rolling highlands.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-emerald-glen',
    name: 'Emerald Glen',
    category: 'Landscapes',
    subtitle: 'A bright green glen at golden hour.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1472214103451-9374bd1c798e?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-violet-shore',
    name: 'Violet Shoreline',
    category: 'Landscapes',
    subtitle: 'Dusk colours over a quiet coast.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1475924156734-496f6cac6ec1?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-teal-summit',
    name: 'Teal Summit',
    category: 'Landscapes',
    subtitle: 'A snowy peak in cool teal haze.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1483728642387-6c3bdd6c93e5?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-red-rock-road',
    name: 'Red Rock Road',
    category: 'Landscapes',
    subtitle: 'An open road through red desert cliffs.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-alpine-lake',
    name: 'Alpine Lake',
    category: 'Landscapes',
    subtitle: 'Turquoise water in the Dolomites.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-shoreline-surf',
    name: 'Shoreline Surf',
    category: 'Landscapes',
    subtitle: 'Waves curling onto pale sand, from above.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1505144808419-1957a94ca61e?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-blue-valley',
    name: 'Blue Valley Dawn',
    category: 'Landscapes',
    subtitle: 'Blue pines and a peach sunrise.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-golden-beach',
    name: 'Golden Beach',
    category: 'Landscapes',
    subtitle: 'Sunset glow on a tropical beach.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-open-water',
    name: 'Open Water',
    category: 'Landscapes',
    subtitle: 'Calm sea, soft light.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1518837695005-2083093ee35b?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-seaside-cliff',
    name: 'Seaside Cliff',
    category: 'Landscapes',
    subtitle: 'A quiet seat above a deep blue sea.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1519125323398-675f0ddb6308?auto=format&fit=crop&w=2400&q=80',
  ),
  BrowserWallpaper(
    id: 'photo-milky-way-peaks',
    name: 'Milky Way Peaks',
    category: 'Landscapes',
    subtitle: 'The galaxy rising over a mountain range.',
    tag: '📷 Photo',
    url: 'https://images.unsplash.com/photo-1519681393784-d120267933ba?auto=format&fit=crop&w=2400&q=80',
  ),

  // --- Solid Colors ---
  BrowserWallpaper(id: 'solid-cobalt', name: 'Cobalt', category: 'Solid colors', subtitle: 'Minimalist deep cobalt shade.', tag: '🎨 Tone', solidColor: Color(0xFF244C9A)),
  BrowserWallpaper(id: 'solid-sage', name: 'Soft sage', category: 'Solid colors', subtitle: 'Soothing organic sage green.', tag: '🎨 Tone', solidColor: Color(0xFF73957B)),
  BrowserWallpaper(id: 'solid-coral', name: 'Coral', category: 'Solid colors', subtitle: 'Warm sunset coral color.', tag: '🎨 Tone', solidColor: Color(0xFFE48673)),
  BrowserWallpaper(id: 'solid-lilac', name: 'Lilac', category: 'Solid colors', subtitle: 'Soft lavender shade for calm reading.', tag: '🎨 Tone', solidColor: Color(0xFF9B85C4)),
  BrowserWallpaper(id: 'solid-amber', name: 'Amber', category: 'Solid colors', subtitle: 'Warm amber glow.', tag: '🎨 Tone', solidColor: Color(0xFFD99A37)),
  BrowserWallpaper(id: 'solid-teal', name: 'Deep teal', category: 'Solid colors', subtitle: 'Tranquil deep ocean teal.', tag: '🎨 Tone', solidColor: Color(0xFF167B78)),
  BrowserWallpaper(id: 'solid-rose', name: 'Rose', category: 'Solid colors', subtitle: 'Gentle rose quartz pastel.', tag: '🎨 Tone', solidColor: Color(0xFFC56883)),
  BrowserWallpaper(id: 'solid-slate', name: 'Blue slate', category: 'Solid colors', subtitle: 'Cool slate gray-blue.', tag: '🎨 Tone', solidColor: Color(0xFF526C83)),
  BrowserWallpaper(id: 'solid-charcoal', name: 'Charcoal', category: 'Solid colors', subtitle: 'Deep matte dark gray.', tag: '🎨 Tone', solidColor: Color(0xFF222428)),

  // --- Windows 11 & Opera Collection ---
  BrowserWallpaper(
    id: 'win11-bloom-light',
    name: 'Windows 11 Bloom Light',
    category: 'Windows 11 & Opera',
    subtitle: 'Iconic Windows 11 acrylic bloom flower light theme.',
    tag: '🪟 Win11 Bloom',
    url: 'https://picsum.photos/seed/win11bloomlight4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'win11-bloom-dark',
    name: 'Windows 11 Bloom Dark',
    category: 'Windows 11 & Opera',
    subtitle: 'Deep dark acrylic motion wave inspired by Windows 11.',
    tag: '🪟 Win11 Dark',
    url: 'https://picsum.photos/seed/win11bloomdark4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'opera-neon-flow',
    name: 'Opera Neon Energy',
    category: 'Windows 11 & Opera',
    subtitle: 'Opera default vibrant glowing cyan and violet energy.',
    tag: '🔴 Opera Neon',
    url: 'https://picsum.photos/seed/operaneon4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'opera-sunset-silk',
    name: 'Opera Sunset Waves',
    category: 'Windows 11 & Opera',
    subtitle: 'Smooth glassmorphism sunset gradient.',
    tag: '🔴 Opera Sunset',
    url: 'https://picsum.photos/seed/operasunset4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'win11-motion-liquid',
    name: 'Windows 11 Liquid Motion',
    category: 'Windows 11 & Opera',
    subtitle: 'Fluid iridescent liquid waves matching Fluent Design.',
    tag: '🪟 Win11 Motion',
    url: 'https://picsum.photos/seed/win11liquid4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'opera-gx-cyber-grid',
    name: 'Opera GX Neon Grid',
    category: 'Windows 11 & Opera',
    subtitle: 'Dark futuristic synthwave grid aesthetic.',
    tag: '🎮 Opera GX',
    url: 'https://picsum.photos/seed/operagxcyber4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'win11-sun-valley',
    name: 'Windows 11 Sun Valley',
    category: 'Windows 11 & Opera',
    subtitle: 'Warm abstract desktop landscape.',
    tag: '🪟 Sun Valley',
    url: 'https://picsum.photos/seed/win11sunvalley4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'opera-frost',
    name: 'Opera Frost Prism',
    category: 'Windows 11 & Opera',
    subtitle: 'Clean geometric frosted glass facets.',
    tag: '🎨 Opera Frost',
    url: 'https://picsum.photos/seed/operafrost4k/1920/1080',
  ),

  // --- Nature Collection ---
  BrowserWallpaper(
    id: 'alpine',
    name: 'Alpine lake',
    category: 'Nature',
    subtitle: 'Serene glacial lake reflecting mountain sky.',
    tag: '🏔️ Theta 6 Hz',
    url: 'https://picsum.photos/seed/naturealpinelake4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'coast',
    name: 'Blue coast',
    category: 'Nature',
    subtitle: 'Azure coastline and rolling ocean waves.',
    tag: '🌊 Alpha 12 Hz',
    url: 'https://picsum.photos/seed/naturebluecoast4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'forest',
    name: 'Forest canopy',
    category: 'Nature',
    subtitle: 'Lush evergreen pine canopy from above.',
    tag: '🌲 Beta 14 Hz',
    url: 'https://picsum.photos/seed/natureforest4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'wildflower',
    name: 'Wildflower morning',
    category: 'Nature',
    subtitle: 'Soft morning light across meadow blossoms.',
    tag: '🌸 Beta 16 Hz',
    url: 'https://picsum.photos/seed/naturewildflower4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'desert',
    name: 'Desert forms',
    category: 'Nature',
    subtitle: 'Sculptural sand dunes bathed in warm sunlight.',
    tag: '🏜️ Gamma 32 Hz',
    url: 'https://picsum.photos/seed/naturedesert4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'mountain',
    name: 'Mountain range',
    category: 'Nature',
    subtitle: 'Snow-covered mountain peaks under crisp sky.',
    tag: '⛰️ Peak Focus',
    url: 'https://picsum.photos/seed/naturemountain4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'forest-lake',
    name: 'Still water',
    category: 'Nature',
    subtitle: 'Mirror lake reflecting calm forest morning.',
    tag: '💧 Deep Calm',
    url: 'https://picsum.photos/seed/naturestillwater4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'northern-lights',
    name: 'Northern lights',
    category: 'Nature',
    subtitle: 'Ethereal green aurora over polar skies.',
    tag: '🌌 Cyber Aurora',
    url: 'https://picsum.photos/seed/natureaurora4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'canyon',
    name: 'Grand Canyon',
    category: 'Nature',
    subtitle: 'Majestic red rock canyon at sunset.',
    tag: '🏜️ Desert Glow',
    url: 'https://picsum.photos/seed/naturecanyon4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'waterfall',
    name: 'Hidden Waterfall',
    category: 'Nature',
    subtitle: 'Crystal clear waterfall deep in the jungle.',
    tag: '🌿 Zen Flow',
    url: 'https://picsum.photos/seed/naturewaterfall4k/1920/1080',
  ),

  // --- Cityscapes Collection ---
  BrowserWallpaper(
    id: 'nyc',
    name: 'New York',
    category: 'Cityscapes',
    subtitle: 'Illuminated Manhattan skyline at twilight.',
    tag: '🏙️ City Dusk',
    url: 'https://picsum.photos/seed/cityscapenyc4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'paris',
    name: 'Paris',
    category: 'Cityscapes',
    subtitle: 'Classic Parisian architecture under warm light.',
    tag: '🗼 Metropolis',
    url: 'https://picsum.photos/seed/cityscapeparis4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'tokyo',
    name: 'Tokyo',
    category: 'Cityscapes',
    subtitle: 'Neon Shibuya lights and futuristic skyline.',
    tag: '🌃 Cyber Tokyo',
    url: 'https://picsum.photos/seed/cityscapetokyo4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'los-angeles',
    name: 'Los Angeles',
    category: 'Cityscapes',
    subtitle: 'Golden hour palms and serene ocean sunset.',
    tag: '🌴 Pacific Light',
    url: 'https://picsum.photos/seed/cityscapela4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'london',
    name: 'London',
    category: 'Cityscapes',
    subtitle: 'Historic Thames skyline and city lights.',
    tag: '🏛️ Metropolitan',
    url: 'https://picsum.photos/seed/cityscapelondon4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'hong-kong',
    name: 'Hong Kong',
    category: 'Cityscapes',
    subtitle: 'Victoria Harbor skyline framed by city peaks.',
    tag: '🌆 Harbor Glow',
    url: 'https://picsum.photos/seed/cityscapehongkong4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'seoul',
    name: 'Seoul',
    category: 'Cityscapes',
    subtitle: 'Vibrant modern city streets and ancient palaces.',
    tag: '🏯 Neon City',
    url: 'https://picsum.photos/seed/cityscapeseoul4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'dubai',
    name: 'Dubai',
    category: 'Cityscapes',
    subtitle: 'Towering skyscrapers above the desert clouds.',
    tag: '🏙️ Future Skyline',
    url: 'https://picsum.photos/seed/cityscapedubai4k/1920/1080',
  ),
  BrowserWallpaper(
    id: 'chicago',
    name: 'Chicago',
    category: 'Cityscapes',
    subtitle: 'The windy city skyline along the lakefront.',
    tag: '🌬️ Windy City',
    url: 'https://picsum.photos/seed/cityscapechicago4k/1920/1080',
  ),

  // --- Space & Night ---
  BrowserWallpaper(id: 'spa-nebula', name: 'Nebula', category: 'Space & Night', subtitle: 'Curated space & night backdrop.', tag: '✨ Space', url: 'https://picsum.photos/seed/cinderspanebula/1920/1080'),
  BrowserWallpaper(id: 'spa-galaxy', name: 'Galaxy', category: 'Space & Night', subtitle: 'Curated space & night backdrop.', tag: '✨ Space', url: 'https://picsum.photos/seed/cinderspagalaxy/1920/1080'),
  BrowserWallpaper(id: 'spa-moonrise', name: 'Moonrise', category: 'Space & Night', subtitle: 'Curated space & night backdrop.', tag: '✨ Space', url: 'https://picsum.photos/seed/cinderspamoonrise/1920/1080'),
  BrowserWallpaper(id: 'spa-starfield', name: 'Starfield', category: 'Space & Night', subtitle: 'Curated space & night backdrop.', tag: '✨ Space', url: 'https://picsum.photos/seed/cinderspastarfield/1920/1080'),
  BrowserWallpaper(id: 'spa-cosmos', name: 'Cosmos', category: 'Space & Night', subtitle: 'Curated space & night backdrop.', tag: '✨ Space', url: 'https://picsum.photos/seed/cinderspacosmos/1920/1080'),
  BrowserWallpaper(id: 'spa-eclipse', name: 'Eclipse', category: 'Space & Night', subtitle: 'Curated space & night backdrop.', tag: '✨ Space', url: 'https://picsum.photos/seed/cinderspaeclipse/1920/1080'),
  BrowserWallpaper(id: 'spa-comet', name: 'Comet', category: 'Space & Night', subtitle: 'Curated space & night backdrop.', tag: '✨ Space', url: 'https://picsum.photos/seed/cinderspacomet/1920/1080'),
  BrowserWallpaper(id: 'spa-milkyway', name: 'Milkyway', category: 'Space & Night', subtitle: 'Curated space & night backdrop.', tag: '✨ Space', url: 'https://picsum.photos/seed/cinderspamilkyway/1920/1080'),

  // --- Abstract & Gradient ---
  BrowserWallpaper(id: 'abs-ember', name: 'Ember', category: 'Abstract & Gradient', subtitle: 'Curated abstract & gradient backdrop.', tag: '✨ Abstract', url: 'https://picsum.photos/seed/cinderabsember/1920/1080'),
  BrowserWallpaper(id: 'abs-glass', name: 'Glass', category: 'Abstract & Gradient', subtitle: 'Curated abstract & gradient backdrop.', tag: '✨ Abstract', url: 'https://picsum.photos/seed/cinderabsglass/1920/1080'),
  BrowserWallpaper(id: 'abs-silk', name: 'Silk', category: 'Abstract & Gradient', subtitle: 'Curated abstract & gradient backdrop.', tag: '✨ Abstract', url: 'https://picsum.photos/seed/cinderabssilk/1920/1080'),
  BrowserWallpaper(id: 'abs-prism', name: 'Prism', category: 'Abstract & Gradient', subtitle: 'Curated abstract & gradient backdrop.', tag: '✨ Abstract', url: 'https://picsum.photos/seed/cinderabsprism/1920/1080'),
  BrowserWallpaper(id: 'abs-ripple', name: 'Ripple', category: 'Abstract & Gradient', subtitle: 'Curated abstract & gradient backdrop.', tag: '✨ Abstract', url: 'https://picsum.photos/seed/cinderabsripple/1920/1080'),
  BrowserWallpaper(id: 'abs-mosaic', name: 'Mosaic', category: 'Abstract & Gradient', subtitle: 'Curated abstract & gradient backdrop.', tag: '✨ Abstract', url: 'https://picsum.photos/seed/cinderabsmosaic/1920/1080'),
  BrowserWallpaper(id: 'abs-aurora-wave', name: 'Aurora Wave', category: 'Abstract & Gradient', subtitle: 'Curated abstract & gradient backdrop.', tag: '✨ Abstract', url: 'https://picsum.photos/seed/cinderabsaurora-wave/1920/1080'),
  BrowserWallpaper(id: 'abs-dusk-blend', name: 'Dusk Blend', category: 'Abstract & Gradient', subtitle: 'Curated abstract & gradient backdrop.', tag: '✨ Abstract', url: 'https://picsum.photos/seed/cinderabsdusk-blend/1920/1080'),

  // --- Minimal & Calm ---
  BrowserWallpaper(id: 'min-fog', name: 'Fog', category: 'Minimal & Calm', subtitle: 'Curated minimal & calm backdrop.', tag: '✨ Minimal', url: 'https://picsum.photos/seed/cinderminfog/1920/1080'),
  BrowserWallpaper(id: 'min-sand', name: 'Sand', category: 'Minimal & Calm', subtitle: 'Curated minimal & calm backdrop.', tag: '✨ Minimal', url: 'https://picsum.photos/seed/cinderminsand/1920/1080'),
  BrowserWallpaper(id: 'min-paper', name: 'Paper', category: 'Minimal & Calm', subtitle: 'Curated minimal & calm backdrop.', tag: '✨ Minimal', url: 'https://picsum.photos/seed/cinderminpaper/1920/1080'),
  BrowserWallpaper(id: 'min-mist', name: 'Mist', category: 'Minimal & Calm', subtitle: 'Curated minimal & calm backdrop.', tag: '✨ Minimal', url: 'https://picsum.photos/seed/cinderminmist/1920/1080'),
  BrowserWallpaper(id: 'min-dawn', name: 'Dawn', category: 'Minimal & Calm', subtitle: 'Curated minimal & calm backdrop.', tag: '✨ Minimal', url: 'https://picsum.photos/seed/cindermindawn/1920/1080'),
  BrowserWallpaper(id: 'min-pebble', name: 'Pebble', category: 'Minimal & Calm', subtitle: 'Curated minimal & calm backdrop.', tag: '✨ Minimal', url: 'https://picsum.photos/seed/cinderminpebble/1920/1080'),
  BrowserWallpaper(id: 'min-linen', name: 'Linen', category: 'Minimal & Calm', subtitle: 'Curated minimal & calm backdrop.', tag: '✨ Minimal', url: 'https://picsum.photos/seed/cinderminlinen/1920/1080'),
  BrowserWallpaper(id: 'min-cloud', name: 'Cloud', category: 'Minimal & Calm', subtitle: 'Curated minimal & calm backdrop.', tag: '✨ Minimal', url: 'https://picsum.photos/seed/cindermincloud/1920/1080'),

  // --- Architecture ---
  BrowserWallpaper(id: 'arc-atrium', name: 'Atrium', category: 'Architecture', subtitle: 'Curated architecture backdrop.', tag: '✨ Architecture', url: 'https://picsum.photos/seed/cinderarcatrium/1920/1080'),
  BrowserWallpaper(id: 'arc-bridge', name: 'Bridge', category: 'Architecture', subtitle: 'Curated architecture backdrop.', tag: '✨ Architecture', url: 'https://picsum.photos/seed/cinderarcbridge/1920/1080'),
  BrowserWallpaper(id: 'arc-spire', name: 'Spire', category: 'Architecture', subtitle: 'Curated architecture backdrop.', tag: '✨ Architecture', url: 'https://picsum.photos/seed/cinderarcspire/1920/1080'),
  BrowserWallpaper(id: 'arc-arches', name: 'Arches', category: 'Architecture', subtitle: 'Curated architecture backdrop.', tag: '✨ Architecture', url: 'https://picsum.photos/seed/cinderarcarches/1920/1080'),
  BrowserWallpaper(id: 'arc-facade', name: 'Facade', category: 'Architecture', subtitle: 'Curated architecture backdrop.', tag: '✨ Architecture', url: 'https://picsum.photos/seed/cinderarcfacade/1920/1080'),
  BrowserWallpaper(id: 'arc-stairs', name: 'Stairs', category: 'Architecture', subtitle: 'Curated architecture backdrop.', tag: '✨ Architecture', url: 'https://picsum.photos/seed/cinderarcstairs/1920/1080'),
  BrowserWallpaper(id: 'arc-skylight', name: 'Skylight', category: 'Architecture', subtitle: 'Curated architecture backdrop.', tag: '✨ Architecture', url: 'https://picsum.photos/seed/cinderarcskylight/1920/1080'),
  BrowserWallpaper(id: 'arc-harbor', name: 'Harbor', category: 'Architecture', subtitle: 'Curated architecture backdrop.', tag: '✨ Architecture', url: 'https://picsum.photos/seed/cinderarcharbor/1920/1080'),
];
