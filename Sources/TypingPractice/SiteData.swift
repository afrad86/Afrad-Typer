import Foundation

/// The practice lists used by the Ngram Type website (Top 200 each), in the same order.
/// Words come first, then n-grams.
enum SiteData {
    static let wordsRaw = """
the be of and a to in he have it that for they I with as not on she at by this we you do but from or which one would all will there say who make when can more if no man out other so what time up go about than into could state only new year some take come these know see use get like then first any work now may such give over think most even find day also after way many must look before great back through long where much should well people down own just because good each those feel seem how high too place little world very still nation hand old life tell write become here show house both between need mean call develop under last right move thing general school never same another begin while number part turn real leave might want point form off child few small since against ask late home interest large person end open public follow during present without again hold govern around possible head consider word program problem however lead system set order eye plan run keep face fact group play stand increase early course change help line
"""

    static let trigramsRaw = """
the and ing ion tio ent ati for her ter hat tha ere ate his con res ver all ons nce men ith ted ers pro thi wit are ess not ive was ect rea com eve per int est sta cti ica ist ear ain one our iti rat nte tin ine der ome man pre rom tra whi ave str act ill ure ide ove cal ble out sti tic oun enc ore ant ity fro art tur par red oth eri hic ies ste ght ich igh und you ort era wer nti oul nde ind tho hou nal but hav uld use han hin een ces cou lat tor ese age ame rin anc ten hen min eas can lit cha ous eat end ssi ial les ren tiv nts whe tat abl dis ran wor rou lin had sed ont ple ugh inc sio din ral ust tan nat ins ass pla ven ell she ose ite lly rec lan ard hey rie pos eme mor den oug tte ned rit ime sin ast any orm ndi ona spe ene hei ric ice ord omp nes sen tim tri ern tes por app lar ntr
"""

    static let tetragramsRaw = """
tion atio that ther with ment ions this here from ould ting hich whic ctio ence have othe ight sion ever ical they inte ough ance were tive over ding pres nter comp able heir thei ally ated ring ture cont ents cons rati thin part form ning ecti some port enti onal itio hing ound will reat comm nder time emen iona more stat stan king been ress thou when acti lati them spec very side thes woul tain nati rate cent ount rese sing what tate even work unde mber hese cial than eral ater tter sent fore ract ling cess inst erat coun ange ties cati late mple into each dent serv only abou tati reas ious ssio most esti ness ctiv lity icat ster ered fere ates lect such arti indi ffer stra ings bout rent eren atte ener atur roug land come soci know also llow rest vers chan ativ ving ined call pers essi efor like gene diff self ause prov ries ilit ffic iden stor evel peri then long cond fect caus rica hose year utio esen ject rodu houg thro oduc irst cted afte tern conc fter firs tabl char once enta
"""


    static func list(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { String($0) }
    }
}
