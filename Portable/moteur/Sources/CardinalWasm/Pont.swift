// Pont entre le moteur et l'interface web : une requête JSON entre, une réponse JSON sort.
nonisolated(unsafe) var derniereReponse: [UInt8] = []

@_expose(wasm, "cardinal_alloc")
@_cdecl("cardinal_alloc")
func cardinalAlloc(_ taille: Int32) -> UnsafeMutablePointer<UInt8> {
    .allocate(capacity: Int(max(taille, 1)))
}

@_expose(wasm, "cardinal_free")
@_cdecl("cardinal_free")
func cardinalFree(_ pointeur: UnsafeMutablePointer<UInt8>) { pointeur.deallocate() }

@_expose(wasm, "cardinal_call")
@_cdecl("cardinal_call")
func cardinalCall(_ pointeur: UnsafeMutablePointer<UInt8>, _ taille: Int32) -> Int32 {
    let requete = Array(UnsafeBufferPointer(start: pointeur, count: Int(taille)))
    derniereReponse = Array(Requetes.traiter(requete))
    return Int32(derniereReponse.count)
}

@_expose(wasm, "cardinal_result")
@_cdecl("cardinal_result")
func cardinalResult() -> UnsafePointer<UInt8>? {
    derniereReponse.withUnsafeBufferPointer { $0.baseAddress }
}
