import React, { useEffect, useRef } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

// Fix Leaflet default icon issue with webpack
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: require('leaflet/dist/images/marker-icon-2x.png'),
  iconUrl: require('leaflet/dist/images/marker-icon.png'),
  shadowUrl: require('leaflet/dist/images/marker-shadow.png'),
});

const KoreaMap = ({ accidents, miniMode = false }) => {
  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersRef = useRef([]);

  useEffect(() => {
    // Initialize map only once
    if (!mapInstanceRef.current) {
      mapInstanceRef.current = L.map(mapRef.current, {
        center: [36.5, 127.5], // Center of South Korea
        zoom: miniMode ? 6.5 : 7,
        minZoom: 6,
        maxZoom: 18,
        zoomControl: !miniMode,
      });

      // Add OpenStreetMap tiles
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        maxZoom: 18,
      }).addTo(mapInstanceRef.current);
    }

    // Clear existing markers
    markersRef.current.forEach(marker => marker.remove());
    markersRef.current = [];

    // Add new markers for accidents
    accidents.forEach((acc) => {
      // altitude is longitude in Korean highway API
      if (!acc.latitude || !acc.altitude) return;

      const lat = parseFloat(acc.latitude);
      const lon = parseFloat(acc.altitude);

      // Validate coordinates
      if (isNaN(lat) || isNaN(lon)) return;
      if (lat < 33 || lat > 39 || lon < 124 || lon > 132) return; // Korea bounds

      // Determine color based on accident type
      let color = '#ef4444'; // red for 사고
      if (!acc.accType) color = '#6b7280'; // gray
      else if (acc.accType.includes('고장')) color = '#f59e0b'; // orange
      else if (acc.accType.includes('작업')) color = '#3b82f6'; // blue
      else if (acc.accType.includes('정체')) color = '#fbbf24'; // amber
      else if (acc.accType.includes('장애물')) color = '#a855f7'; // purple

      // Create custom icon with pulsing animation
      const customIcon = L.divIcon({
        className: 'custom-marker',
        html: `
          <div style="position: relative;">
            <div style="
              position: absolute;
              width: 20px;
              height: 20px;
              border-radius: 50%;
              background-color: ${color};
              opacity: 0.6;
              animation: pulse 1.5s infinite;
            "></div>
            <div style="
              position: absolute;
              width: 12px;
              height: 12px;
              margin: 4px;
              border-radius: 50%;
              background-color: ${color};
              border: 2px solid white;
              box-shadow: 0 0 4px rgba(0,0,0,0.3);
            "></div>
          </div>
        `,
        iconSize: [20, 20],
        iconAnchor: [10, 10],
      });

      const marker = L.marker([lat, lon], { icon: customIcon })
        .bindPopup(`
          <div style="font-family: sans-serif; min-width: 200px;">
            <h3 style="margin: 0 0 8px 0; color: ${color}; font-size: 14px; font-weight: bold;">
              ${acc.accType || '정보 없음'}
            </h3>
            <p style="margin: 4px 0; font-size: 12px;">
              <strong>위치:</strong> ${acc.accPointNM || acc.roadNM || '위치 정보 없음'}
            </p>
            ${acc.roadNM && acc.nosunNM ? `<p style="margin: 4px 0; font-size: 12px;"><strong>노선:</strong> ${acc.roadNM} (${acc.nosunNM})</p>` : ''}
            <p style="margin: 4px 0; font-size: 12px;">
              <strong>내용:</strong> ${acc.smsText || acc.accInfo || '상세 정보 없음'}
            </p>
            <p style="margin: 4px 0; font-size: 12px; color: #666;">
              ${acc.accDate} ${acc.accHour}
            </p>
          </div>
        `)
        .addTo(mapInstanceRef.current);

      markersRef.current.push(marker);
    });

    // Cleanup function
    return () => {
      // Don't destroy map on updates, only markers
    };
  }, [accidents]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (mapInstanceRef.current) {
        mapInstanceRef.current.remove();
        mapInstanceRef.current = null;
      }
    };
  }, []);

  return (
    <div className="relative w-full">
      <style>{`
        @keyframes pulse {
          0% {
            transform: scale(0.5);
            opacity: 0.8;
          }
          50% {
            transform: scale(1.5);
            opacity: 0.3;
          }
          100% {
            transform: scale(2);
            opacity: 0;
          }
        }
        .custom-marker {
          background: none;
          border: none;
        }
        .leaflet-container {
          background: ${miniMode ? 'linear-gradient(to bottom right, #eff6ff, #ecfdf5)' : '#1e293b'};
        }
      `}</style>

      {/* Map Container */}
      <div
        ref={mapRef}
        className="w-full rounded-lg"
        style={{
          height: miniMode ? '200px' : '600px',
          border: miniMode ? '1px solid #e5e7eb' : '2px solid #475569'
        }}
      />

      {/* Legend - Only show in full mode */}
      {!miniMode && (
        <div className="mt-4 flex flex-wrap gap-4 text-sm">
          <div className="flex items-center">
            <div className="w-3 h-3 rounded-full bg-red-500 mr-2"></div>
            <span>사고</span>
          </div>
          <div className="flex items-center">
            <div className="w-3 h-3 rounded-full bg-orange-500 mr-2"></div>
            <span>고장</span>
          </div>
          <div className="flex items-center">
            <div className="w-3 h-3 rounded-full bg-blue-500 mr-2"></div>
            <span>작업</span>
          </div>
          <div className="flex items-center">
            <div className="w-3 h-3 rounded-full bg-amber-400 mr-2"></div>
            <span>정체</span>
          </div>
          <div className="flex items-center">
            <div className="w-3 h-3 rounded-full bg-purple-500 mr-2"></div>
            <span>장애물</span>
          </div>
        </div>
      )}

      {/* Accident Count - Only show in full mode */}
      {!miniMode && (
        <div className="mt-4 text-center">
          <div className="inline-block bg-slate-700/50 px-6 py-2 rounded-full">
            <span className="text-slate-400">현재 사고 건수: </span>
            <span className="text-green-400 font-bold text-xl">{accidents.length}</span>
          </div>
        </div>
      )}
    </div>
  );
};

export default KoreaMap;
