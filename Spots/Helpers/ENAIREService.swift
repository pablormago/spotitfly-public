import Foundation

class ENAIREService {
    private let urlString =
    "https://servais.enaire.es/insignia/services/NSF_SRV/SRV_UAS_ZG_V1/MapServer/WFSServer?service=WFS&version=2.0.0&request=GetFeature&typeName=ZGUAS_Aero"

    func fetchRestricciones(completion: @escaping (Result<[ENAIREFeature], Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "URL inválida", code: -1)))
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "Sin datos", code: -1)))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ENAIRECollection.self, from: data)
                print("✅ Features:", decoded.features.count)
                completion(.success(decoded.features))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
