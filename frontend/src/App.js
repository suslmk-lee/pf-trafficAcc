import React, { useState, useEffect } from 'react';
import KoreaMap from './components/KoreaMap';
import AccidentList from './components/AccidentList';
import StatsPanel from './components/StatsPanel';
import TollgateTrafficPanel from './components/TollgateTrafficPanel';
import RoadRouteSummaryPanel from './components/RoadRouteSummaryPanel';
import DashboardPanel from './components/DashboardPanel';
import { fetchWithRetry } from './utils/fetchWithRetry';
import { healthMonitor } from './utils/healthCheck';

function App() {
  const [activeTab, setActiveTab] = useState('dashboard'); // 'dashboard', 'accidents', 'tollgate', or 'roadstatus'
  const [accidents, setAccidents] = useState([]);
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastUpdate, setLastUpdate] = useState(null);
  const [isInitialLoad, setIsInitialLoad] = useState(true);

  // Use relative path since frontend and API are served from same IngressGateway
  const API_GATEWAY_URL = process.env.REACT_APP_API_GATEWAY_URL || '';

  // Initial load: fetch recent accidents (3 hours worth, typically 20-50 accidents)
  const fetchInitialAccidents = async () => {
    try {
      const response = await fetchWithRetry(`${API_GATEWAY_URL}/api/accidents/latest?limit=100`, {
        timeout: 15000,
      }, 3);
      const data = await response.json();

      if (data && data.length > 0) {
        setAccidents(data);
      }

      setLastUpdate(new Date());
      setError(null);
      setIsInitialLoad(false);
    } catch (err) {
      console.error('Error fetching initial accidents:', err);
      setError(err.message);
      setIsInitialLoad(false);
    } finally {
      setLoading(false);
    }
  };

  // Polling: check for new accidents
  const fetchAccidents = async () => {
    try {
      const response = await fetchWithRetry(`${API_GATEWAY_URL}/api/accidents/latest?limit=1`, {
        timeout: 10000,
      }, 2);
      const data = await response.json();

      if (data && data.length > 0) {
        const newAccident = data[0];

        setAccidents(prev => {
          // Check if this accident already exists
          const exists = prev.some(acc => acc.id === newAccident.id);

          if (!exists) {
            // Add new accident at the beginning (maintains newest-first order)
            return [newAccident, ...prev];
          }

          return prev;
        });
      }

      setLastUpdate(new Date());
      setError(null);
    } catch (err) {
      console.error('Error fetching accidents:', err);
      setError(err.message);
    }
  };

  const fetchStats = async () => {
    try {
      const response = await fetchWithRetry(`${API_GATEWAY_URL}/api/accidents/stats`, {
        timeout: 10000,
      }, 2);
      const data = await response.json();
      setStats(data);
    } catch (err) {
      console.error('Error fetching stats:', err);
    }
  };

  useEffect(() => {
    // Initial load
    fetchInitialAccidents();
    fetchStats();

    // Start health monitoring for GSLB failover
    healthMonitor.start();

    // Poll every 10 seconds for new accidents
    const interval = setInterval(() => {
      fetchAccidents();
      fetchStats();
    }, 10000);

    return () => {
      clearInterval(interval);
      healthMonitor.stop();
    };
  }, []);

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 flex flex-col">
      {/* Navigation Menu - Fixed at Top */}
      <div className="absolute top-0 right-0 z-20 flex items-start gap-2 pr-6">
        {/* Dashboard Button */}
        <button
          onClick={() => setActiveTab('dashboard')}
          className={`transition-all duration-400 ease-out ${
            activeTab === 'dashboard' ? 'h-20' : 'h-14'
          } w-20`}
        >
          <div className={`h-full flex items-center justify-center rounded-b-2xl border-b-4 border-x-2 border-t-0 transition-all duration-300 ${
            activeTab === 'dashboard'
              ? 'bg-blue-600 border-blue-400 shadow-lg'
              : 'bg-slate-800/90 border-slate-700 hover:border-slate-500 hover:bg-slate-700/90'
          }`}>
            <span className={`text-sm font-bold tracking-tight ${activeTab === 'dashboard' ? 'text-white' : 'text-slate-300'}`}>
              대시보드
            </span>
          </div>
        </button>

        {/* Accidents Button */}
        <button
          onClick={() => setActiveTab('accidents')}
          className={`transition-all duration-400 ease-out ${
            activeTab === 'accidents' ? 'h-20' : 'h-14'
          } w-20`}
        >
          <div className={`h-full flex items-center justify-center rounded-b-2xl border-b-4 border-x-2 border-t-0 transition-all duration-300 ${
            activeTab === 'accidents'
              ? 'bg-red-600 border-red-400 shadow-lg'
              : 'bg-slate-800/90 border-slate-700 hover:border-slate-500 hover:bg-slate-700/90'
          }`}>
            <span className={`text-sm font-bold tracking-tight ${activeTab === 'accidents' ? 'text-white' : 'text-slate-300'}`}>
              교통사고
            </span>
          </div>
        </button>

        {/* Tollgate Button */}
        <button
          onClick={() => setActiveTab('tollgate')}
          className={`transition-all duration-400 ease-out ${
            activeTab === 'tollgate' ? 'h-20' : 'h-14'
          } w-20`}
        >
          <div className={`h-full flex items-center justify-center rounded-b-2xl border-b-4 border-x-2 border-t-0 transition-all duration-300 ${
            activeTab === 'tollgate'
              ? 'bg-green-600 border-green-400 shadow-lg'
              : 'bg-slate-800/90 border-slate-700 hover:border-slate-500 hover:bg-slate-700/90'
          }`}>
            <span className={`text-sm font-bold tracking-tight ${activeTab === 'tollgate' ? 'text-white' : 'text-slate-300'}`}>
              요금소
            </span>
          </div>
        </button>

        {/* Road Status Button */}
        <button
          onClick={() => setActiveTab('roadstatus')}
          className={`transition-all duration-400 ease-out ${
            activeTab === 'roadstatus' ? 'h-20' : 'h-14'
          } w-20`}
        >
          <div className={`h-full flex items-center justify-center rounded-b-2xl border-b-4 border-x-2 border-t-0 transition-all duration-300 ${
            activeTab === 'roadstatus'
              ? 'bg-purple-600 border-purple-400 shadow-lg'
              : 'bg-slate-800/90 border-slate-700 hover:border-slate-500 hover:bg-slate-700/90'
          }`}>
            <span className={`text-sm font-bold tracking-tight ${activeTab === 'roadstatus' ? 'text-white' : 'text-slate-300'}`}>
              실시간
            </span>
          </div>
        </button>
      </div>

      {/* Header with Title */}
      <header className="relative bg-gradient-to-r from-slate-800/70 via-slate-800/50 to-slate-800/70 backdrop-blur-sm border-b-2 border-slate-600 px-6 py-5 mt-0 z-10 shadow-lg">
        <div className="flex items-center justify-between">
          {/* Left: Title */}
          <div className="flex-shrink-0">
            <div className="flex items-center gap-4">
              {/* K-PaaS Logo */}
              <div className="relative group">
                <div className="absolute inset-0 bg-gradient-to-br from-blue-400/30 via-purple-400/30 to-pink-400/30 rounded-xl blur-md opacity-70 group-hover:opacity-100 transition-opacity"></div>
                <div className="relative bg-gradient-to-br from-slate-700/80 to-slate-800/80 backdrop-blur-sm rounded-xl px-4 py-2.5 border border-slate-600/50 shadow-lg">
                  <img
                    src="/logo_k-paas.png"
                    alt="K-PaaS Logo"
                    className="h-10 w-auto brightness-0 invert opacity-90"
                  />
                </div>
              </div>

              {/* Title */}
              <div>
                <h1 className="text-3xl font-black text-white leading-tight tracking-tight">
                  실시간 고속도로 교통정보
                </h1>
                <p className="text-slate-400 text-sm mt-1 font-medium tracking-wide">
                  <span className="text-blue-400">PlugFest 2025</span> - High Availability Demo
                </p>
              </div>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="flex-1 overflow-auto p-4">

        {activeTab === 'dashboard' ? (
          <DashboardPanel
            onNavigate={setActiveTab}
            accidents={accidents}
            stats={stats}
          />
        ) : activeTab === 'accidents' ? (
          loading && !error ? (
            <div className="flex items-center justify-center h-96">
              <div className="text-center">
                <div className="animate-spin rounded-full h-16 w-16 border-b-2 border-green-500 mx-auto"></div>
                <p className="mt-4 text-slate-400">데이터 로딩 중...</p>
              </div>
            </div>
          ) : (
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
              {/* Left Column - Map */}
              <div className="lg:col-span-2 space-y-6">
                {error && (
                  <div className="bg-red-900/20 border border-red-500 text-red-300 px-4 py-3 rounded">
                    <strong className="font-bold">오류: </strong>
                    <span>{error}</span>
                  </div>
                )}

                <div className="bg-slate-800/50 backdrop-blur-sm rounded-lg shadow-xl p-6 border border-slate-700">
                  <h2 className="text-xl font-bold mb-4 flex items-center justify-between">
                    <span className="flex items-center">
                      <span className="mr-2">🗺️</span>
                      대한민국 고속도로 사고 현황
                    </span>
                    <span className="text-sm font-normal text-slate-400">
                      최근 3시간 이내
                    </span>
                  </h2>
                  <KoreaMap accidents={accidents} />
                </div>

                {stats && <StatsPanel stats={stats} />}
              </div>

              {/* Right Column - Accidents List */}
              <div className="space-y-6">
                <AccidentList accidents={accidents} />
              </div>
            </div>
          )
        ) : activeTab === 'tollgate' ? (
          <TollgateTrafficPanel />
        ) : (
          <RoadRouteSummaryPanel />
        )}
      </main>
    </div>
  );
}

export default App;
