import React from 'react';

const AccidentList = ({ accidents }) => {
  const getAccidentTypeIcon = (type) => {
    if (!type) return '⚠️';

    if (type.includes('사고')) return '🚨';
    if (type.includes('고장')) return '🔧';
    if (type.includes('장애물')) return '📦';
    if (type.includes('작업')) return '🚧';
    if (type.includes('정체')) return '🚗';
    return '⚠️';
  };

  const getAccidentTypeColor = (type) => {
    if (!type) return 'text-yellow-400 bg-yellow-900/30 border-yellow-500';

    if (type.includes('사고')) return 'text-red-400 bg-red-900/30 border-red-500';
    if (type.includes('고장')) return 'text-orange-400 bg-orange-900/30 border-orange-500';
    if (type.includes('장애물')) return 'text-purple-400 bg-purple-900/30 border-purple-500';
    if (type.includes('작업')) return 'text-blue-400 bg-blue-900/30 border-blue-500';
    if (type.includes('정체')) return 'text-amber-400 bg-amber-900/30 border-amber-500';
    return 'text-yellow-400 bg-yellow-900/30 border-yellow-500';
  };

  const formatDateTime = (accDate, accHour) => {
    if (!accDate || !accHour) return '';

    // accDate: YYYY.MM.DD or YYYYMMDD
    // accHour: HH:MM:SS or HHMM
    let formattedDate = accDate;
    let formattedTime = accHour;

    // If YYYYMMDD format, convert to YYYY.MM.DD
    if (accDate.length === 8 && !accDate.includes('.')) {
      const year = accDate.substring(0, 4);
      const month = accDate.substring(4, 6);
      const day = accDate.substring(6, 8);
      formattedDate = `${year}.${month}.${day}`;
    }

    // If HHMM format, convert to HH:MM
    if (accHour.length === 4 && !accHour.includes(':')) {
      const hour = accHour.substring(0, 2);
      const minute = accHour.substring(2, 4);
      formattedTime = `${hour}:${minute}`;
    }

    return `${formattedDate} ${formattedTime}`;
  };

  return (
    <div className="bg-slate-800/50 backdrop-blur-sm rounded-lg shadow-xl p-6 border border-slate-700">
      <h2 className="text-xl font-bold mb-4 flex items-center justify-between">
        <span className="flex items-center">
          <span className="mr-2">📋</span>
          실시간 사고 목록
          <span className="ml-2 text-xs font-normal text-slate-500">(최근 3시간)</span>
        </span>
        <span className="text-sm font-normal text-slate-400">
          총 {accidents.length}건
        </span>
      </h2>

      <div className="space-y-3 max-h-[600px] overflow-y-auto pr-2 custom-scrollbar">
        {accidents.length === 0 ? (
          <div className="text-center py-12 text-slate-400">
            <div className="text-4xl mb-2">✅</div>
            <p>현재 사고 정보가 없습니다</p>
          </div>
        ) : (
          accidents.map((accident, index) => (
            <div
              key={`${accident.id}-${index}`}
              className={`p-4 rounded-lg border transition-all hover:scale-[1.02] ${getAccidentTypeColor(
                accident.accType
              )}`}
            >
              <div className="flex items-start justify-between mb-2">
                <div className="flex items-center">
                  <span className="text-2xl mr-2">
                    {getAccidentTypeIcon(accident.accType)}
                  </span>
                  <div>
                    <h3 className="font-bold">{accident.accType || '정보 없음'}</h3>
                    <p className="text-sm opacity-80">
                      {accident.accPointNM || accident.roadNM || '위치 정보 없음'}
                      {accident.roadNM && accident.nosunNM && ` (${accident.nosunNM})`}
                    </p>
                  </div>
                </div>
              </div>

              <div className="ml-10 space-y-1 text-sm">
                <p className="opacity-90">{accident.smsText || accident.accInfo || '상세 정보 없음'}</p>
                <p className="opacity-70 text-xs font-mono">
                  {formatDateTime(accident.accDate, accident.accHour)}
                </p>
              </div>
            </div>
          ))
        )}
      </div>

      <style>{`
        .custom-scrollbar::-webkit-scrollbar {
          width: 8px;
        }
        .custom-scrollbar::-webkit-scrollbar-track {
          background: rgba(51, 65, 85, 0.3);
          border-radius: 4px;
        }
        .custom-scrollbar::-webkit-scrollbar-thumb {
          background: rgba(100, 116, 139, 0.5);
          border-radius: 4px;
        }
        .custom-scrollbar::-webkit-scrollbar-thumb:hover {
          background: rgba(100, 116, 139, 0.7);
        }
      `}</style>
    </div>
  );
};

export default AccidentList;
